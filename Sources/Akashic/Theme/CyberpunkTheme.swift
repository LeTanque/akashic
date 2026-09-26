import AppKit
import SwiftUI

enum CyberpunkTheme {
    /// Electric blue — borders, text, buttons, title, glow (`#00d9ff`).
    static let neonCyan = Color(red: 0, green: 217 / 255, blue: 1)
    /// Completed text / button hover fill / low priority (`#18484e`).
    static let completedShaded = Color(red: 24 / 255, green: 72 / 255, blue: 78 / 255)
    /// High priority accent — neon orange on black (`#ff7a1a`).
    static let neonOrange = Color(red: 1, green: 122 / 255, blue: 26 / 255)
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
    /// Bottom corners of the frameless main window shell (~macOS default).
    static let windowBottomCornerRadius: CGFloat = 11
    /// Space between window edge and neon frame (room for outer glow / shadows).
    static let windowNeonGlowClearance: CGFloat = 14
    /// Padding inside the neon stroke before app content.
    static let windowNeonContentInset: CGFloat = 16
    /// Main window header wildstyle wordmark height.
    static let headerWordmarkHeight: CGFloat = 38
    /// Optical vertical nudge (wordmark reads low vs square header buttons).
    static let headerWordmarkVerticalOffset: CGFloat = -3

    static func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high:
            neonOrange
        case .medium:
            neonCyan
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
            .background {
                ZStack {
                    GlassBackground(material: .hudWindow, blendingMode: .behindWindow)
                    Color.black.opacity(0.4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Square top corners; bottom corners match the macOS window shell radius.
struct NeonWindowShellShape: InsettableShape {
    var bottomCornerRadius: CGFloat = CyberpunkTheme.windowBottomCornerRadius
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = max(0, bottomCornerRadius - insetAmount)
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: r,
            bottomTrailingRadius: r,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> NeonWindowShellShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Approximates cyberpunk2044 CSS outer + inset neon glow (not pixel-identical to box-shadow).
struct NeonWindowFrameModifier: ViewModifier {
    var contentInset: CGFloat = CyberpunkTheme.windowNeonContentInset
    var glowClearance: CGFloat = CyberpunkTheme.windowNeonGlowClearance

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .padding(contentInset)
            .background {
                SmokedGlassFill(material: .hudWindow, smokeOpacity: 0.38)
            }
            .clipShape(NeonWindowShellShape())
            .overlay {
                NeonWindowShellShape()
                    .stroke(CyberpunkTheme.neonCyan.opacity(0.35), lineWidth: 5)
                    .blur(radius: 4)
                    .allowsHitTesting(false)
            }
            .overlay {
                NeonWindowShellShape()
                    .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
                    .shadow(color: CyberpunkTheme.neonCyan.opacity(0.65), radius: 7)
                    .shadow(color: CyberpunkTheme.neonCyan.opacity(0.25), radius: 14)
                    .allowsHitTesting(false)
            }
            .padding(glowClearance)
    }
}

private enum AkashicHeaderWordmark {
    static func loadNSImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "akashic-logo-wildstyle", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct AkashicHeaderWordmarkView: View {
    var body: some View {
        Group {
            if let nsImage = AkashicHeaderWordmark.loadNSImage() {
                Image(nsImage: nsImage)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: CyberpunkTheme.headerWordmarkHeight)
                    .background(Color.clear)
            } else {
                Text("Akashic")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(CyberpunkTheme.neonCyan)
            }
        }
        .accessibilityLabel("Akashic")
    }
}

struct CyberHeaderStrip<Trailing: View>: View {
    @ViewBuilder var trailing: () -> Trailing

    init(@ViewBuilder trailing: @escaping () -> Trailing) {
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                AkashicHeaderWordmarkView()
                    .offset(y: CyberpunkTheme.headerWordmarkVerticalOffset)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 0)
            .padding(.bottom, 10)
            .background(WindowDragRegion())
            Rectangle()
                .fill(CyberpunkTheme.neonCyan)
                .frame(height: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.5), radius: 4)
        }
        .background(Color.black.opacity(0.18))
    }
}

struct CyberBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CyberBorderedButtonBody(configuration: configuration, accent: CyberpunkTheme.neonCyan)
    }
}

/// Danger-tinted bordered button (e.g. delete in the editor).
struct CyberDestructiveBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CyberBorderedButtonBody(configuration: configuration, accent: CyberpunkTheme.neonOrange)
    }
}

private struct CyberBorderedButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let accent: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(accent.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundFill)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: isHovered && isEnabled ? accent.opacity(0.35) : .clear, radius: 4)
            .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        guard isEnabled else {
            return CyberpunkTheme.completedShaded.opacity(0.15)
        }
        if configuration.isPressed {
            return accent.opacity(0.28)
        }
        if isHovered {
            return accent.opacity(0.18)
        }
        return CyberpunkTheme.background
    }

    private var borderColor: Color {
        accent.opacity(isEnabled ? (isHovered ? 1 : 0.9) : 0.4)
    }
}

/// Fixed square chrome for header icon buttons (Add, import, close).
struct CyberHeaderIconButtonStyle: ButtonStyle {
    static let size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        CyberHeaderIconButtonBody(configuration: configuration)
    }
}

private struct CyberHeaderIconButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(CyberpunkTheme.neonCyan.opacity(isEnabled ? 1 : 0.45))
            .frame(width: CyberHeaderIconButtonStyle.size, height: CyberHeaderIconButtonStyle.size)
            .background(backgroundFill)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: isHovered && isEnabled ? 1.5 : 1)
            )
            .shadow(color: isHovered && isEnabled ? CyberpunkTheme.neonCyan.opacity(0.4) : .clear, radius: 5)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        guard isEnabled else {
            return CyberpunkTheme.completedShaded.opacity(0.15)
        }
        if configuration.isPressed {
            return CyberpunkTheme.completedShaded.opacity(0.35)
        }
        if isHovered {
            return CyberpunkTheme.completedShaded.opacity(0.28)
        }
        return CyberpunkTheme.background
    }

    private var borderColor: Color {
        CyberpunkTheme.neonCyan.opacity(isEnabled ? (isHovered ? 1 : 0.95) : 0.4)
    }
}

extension View {
    func cyberPanel(cornerRadius: CGFloat = 0) -> some View {
        modifier(CyberPanelModifier(cornerRadius: cornerRadius))
    }

    func neonWindowFrame(
        contentInset: CGFloat = CyberpunkTheme.windowNeonContentInset,
        glowClearance: CGFloat = CyberpunkTheme.windowNeonGlowClearance
    ) -> some View {
        modifier(NeonWindowFrameModifier(contentInset: contentInset, glowClearance: glowClearance))
    }
}
