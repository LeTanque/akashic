import SwiftUI

enum CyberpunkTheme {
    /// Electric blue — borders, text, buttons, title, glow (`#00d9ff`).
    static let neonCyan = Color(red: 0, green: 217 / 255, blue: 1)
    /// Completed text / button hover fill (`#18484e`).
    static let completedShaded = Color(red: 24 / 255, green: 72 / 255, blue: 78 / 255)
    /// Row dividers (`#333333`).
    static let rowDivider = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    /// Window / panel fill (`#000000`).
    static let background = Color.black
    /// Slightly lifted body tone (`#0a0a0a`).
    static let bodyBackground = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    static let textPrimary = neonCyan
    static let textSecondary = completedShaded
    static let border = neonCyan
    static let panel = background

    static func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high:
            neonCyan.opacity(1)
        case .medium:
            neonCyan.opacity(0.75)
        case .low:
            completedShaded
        }
    }
}

// MARK: - Chrome modifiers

struct CyberPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(CyberpunkTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Approximates cyberpunk2044 CSS outer + inset neon glow (not pixel-identical to box-shadow).
struct NeonWindowFrameModifier: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(CyberpunkTheme.background)
            .overlay {
                Rectangle()
                    .stroke(CyberpunkTheme.neonCyan.opacity(0.35), lineWidth: 5)
                    .padding(-3)
                    .blur(radius: 4)
                    .allowsHitTesting(false)
            }
            .overlay {
                Rectangle()
                    .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: CyberpunkTheme.neonCyan.opacity(0.65), radius: 7)
            .shadow(color: CyberpunkTheme.neonCyan.opacity(0.25), radius: 14)
    }
}

struct CyberHeaderStrip: View {
    var title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(CyberpunkTheme.neonCyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Rectangle()
                .fill(CyberpunkTheme.neonCyan)
                .frame(height: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.5), radius: 4)
        }
        .background(CyberpunkTheme.background)
    }
}

struct CyberBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(CyberpunkTheme.neonCyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed || !isEnabled
                ? CyberpunkTheme.completedShaded.opacity(isEnabled ? 0.35 : 0.15)
                : CyberpunkTheme.background)
            .overlay(
                Rectangle()
                    .stroke(CyberpunkTheme.neonCyan.opacity(isEnabled ? 1 : 0.4), lineWidth: 1)
            )
    }
}

extension View {
    func cyberPanel(cornerRadius: CGFloat = 0) -> some View {
        modifier(CyberPanelModifier(cornerRadius: cornerRadius))
    }

    func neonWindowFrame(padding: CGFloat = 12) -> some View {
        modifier(NeonWindowFrameModifier(padding: padding))
    }
}
