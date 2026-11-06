import AppKit
import SwiftUI

struct AkashicFirstRunView: View {
    @ObservedObject var vault: AkashicVaultController

    var body: some View {
        VStack(spacing: 20) {
            Text("AKASHIC · SETUP")
                .font(.custom("Menlo-Bold", size: 18))
                .foregroundStyle(CyberpunkTheme.neonCyan)

            switch vault.firstRunStep {
            case .credentials:
                credentialsStep
            case .codes:
                codesStep
            case .confirm:
                confirmStep
            }

            if let err = vault.setupError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.neonOrange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(32)
        .frame(minWidth: 440, minHeight: 520)
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            CyberField(title: "USERNAME", text: $vault.setupUsername, contentType: .username)
            CyberSecureField(title: "PASSWORD (min 8)", text: $vault.setupPassword, contentType: .password)
            CyberSecureField(title: "CONFIRM PASSWORD", text: $vault.setupConfirmPassword, contentType: .password)
            CyberButton(title: "CONTINUE") {
                vault.advanceFirstRunToCodes()
            }
        }
    }

    private var codesStep: some View {
        VStack(spacing: 16) {
            Text("Save your recovery code offline. Shown once.")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            Text(vault.setupRecoveryDisplay)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(CyberpunkTheme.neonCyan)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            VStack(spacing: 8) {
                Text("Scan this QR in Passwords or any authenticator")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.readableMutedCyan)
                AkashicQRImageView(payload: vault.setupOtpauthURI)
            }

            CyberButton(title: "I SAVED THESE · CONTINUE") {
                vault.advanceFirstRunToConfirm()
            }
        }
    }

    private var confirmStep: some View {
        VStack(spacing: 14) {
            Text("Enter the 6-digit code from your authenticator")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            CyberField(title: "6-DIGIT CODE", text: $vault.setupTOTPCode, contentType: .oneTimeCode)
            CyberButton(title: "FINISH SETUP") {
                Task { await vault.completeFirstRunAfterTOTP() }
            }
            Button("Back") {
                vault.goBackFromFirstRunConfirmToCodes()
            }
            .buttonStyle(.plain)
            .foregroundStyle(CyberpunkTheme.readableMutedCyan)
        }
    }
}

private struct CyberField: View {
    let title: String
    @Binding var text: String
    var contentType: NSTextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.black.opacity(0.35))
                .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.5), lineWidth: 1))
                .foregroundStyle(CyberpunkTheme.neonCyan)
                .font(.system(.body, design: .monospaced))
                .applyNSTextContentType(contentType)
        }
    }
}

private struct CyberSecureField: View {
    let title: String
    @Binding var text: String
    var contentType: NSTextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.black.opacity(0.35))
                .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.5), lineWidth: 1))
                .foregroundStyle(CyberpunkTheme.neonCyan)
                .font(.system(.body, design: .monospaced))
                .applyNSTextContentType(contentType)
        }
    }
}

private struct CyberButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Menlo-Bold", size: 11))
                .foregroundStyle(CyberpunkTheme.neonCyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.4))
                .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.85), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func applyNSTextContentType(_ type: NSTextContentType?) -> some View {
        if let type {
            self.textContentType(type)
        } else {
            self
        }
    }
}
