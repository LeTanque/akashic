import AppKit
import SwiftUI

struct AkashicUnlockView: View {
    @ObservedObject var vault: AkashicVaultController
    @State private var useRecovery = false

    var body: some View {
        VStack(spacing: 18) {
            Text("AKASHIC · UNLOCK")
                .font(.custom("Menlo-Bold", size: 18))
                .foregroundStyle(CyberpunkTheme.neonCyan)

            Text("User: \(vault.unlockUsername)")
                .font(.caption)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)

            VStack(alignment: .leading, spacing: 12) {
                if useRecovery {
                    unlockField(title: "RECOVERY CODE", secure: false, text: $vault.unlockRecoveryCode, contentType: NSTextContentType?.none)
                } else {
                    unlockField(title: "PASSWORD", secure: true, text: $vault.unlockPassword, contentType: .password)
                }
                unlockField(title: "6-DIGIT CODE", secure: false, text: $vault.unlockTOTP, contentType: .oneTimeCode)
            }

            Toggle("Use recovery code instead of password", isOn: $useRecovery)
                .toggleStyle(.switch)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)

            Toggle("Use Touch ID after unlock (this device)", isOn: Binding(
                get: { vault.biometricUnlockEnabled },
                set: { vault.updateBiometricPreference(enabled: $0) }
            ))
            .toggleStyle(.switch)
            .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                unlockButton("UNLOCK") {
                    Task {
                        if useRecovery {
                            await vault.unlockWithRecovery()
                        } else {
                            await vault.unlock()
                        }
                    }
                }
                if vault.biometricUnlockEnabled && !useRecovery {
                    unlockButton("TOUCH ID") {
                        Task { await vault.unlockWithBiometrics() }
                    }
                }
            }

            if let err = vault.unlockError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.neonOrange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 400)
    }

    private func unlockField(
        title: String,
        secure: Bool,
        text: Binding<String>,
        contentType: NSTextContentType?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .padding(8)
            .background(Color.black.opacity(0.35))
            .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.5), lineWidth: 1))
            .foregroundStyle(CyberpunkTheme.neonCyan)
            .font(.system(.body, design: .monospaced))
            .applyContentType(contentType)
        }
    }

    private func unlockButton(_ title: String, action: @escaping () -> Void) -> some View {
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
    func applyContentType(_ type: NSTextContentType?) -> some View {
        if let type {
            self.textContentType(type)
        } else {
            self
        }
    }
}
