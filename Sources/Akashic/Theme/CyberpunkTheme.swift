import AppKit
import Foundation
import SwiftUI

enum CyberpunkTheme {
    /// Electric blue — borders, text, buttons, title, glow (`#00d9ff`).
    static let neonCyan = Color(red: 0, green: 217 / 255, blue: 1)
    /// Completed text / button hover fill / low priority (`#18484e`).
    static let completedShaded = Color(red: 24 / 255, green: 72 / 255, blue: 78 / 255)
    /// Readable muted cyan on `background` / dark panels — metadata, due-date labels (`#3d96a4`).
    static let readableMutedCyan = Color(red: 61 / 255, green: 150 / 255, blue: 164 / 255)
    /// Incomplete todo description in the sidebar list (same hue as `readableMutedCyan`).
    static let activeTodoDescription = readableMutedCyan
    /// Secondary labels and weekday headers in the due-date picker panel.
    static let dueDatePickerMutedText = readableMutedCyan
    /// Inactive cell / stepper borders in the due-date picker (brighter than low-opacity neon).
    static let dueDatePickerInactiveBorder = readableMutedCyan
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
    /// Extra smoke over leftover titlebar / top chrome (on top of the 0.38 window veil).
    static let windowTopChromeVeilOpacity: Double = 0.45
    /// Typical ~28pt titlebar plus the 16pt content inset, fading into the header.
    static let windowTopChromeVeilHeight: CGFloat = 52
    /// Main window header wildstyle wordmark height (tall enough for three metric rows beside it).
    static let headerWordmarkHeight: CGFloat = 48
    /// Optical vertical nudge (wordmark reads low vs square header buttons).
    static let headerWordmarkVerticalOffset: CGFloat = -3
    /// Tight pad above/below the wordmark–metrics–buttons row (not a tall empty band).
    static let headerStripVerticalPadding: CGFloat = 4
    /// Header row sits on the neon content inset; no extra leading inset before metrics.
    static let headerStripLeadingPadding: CGFloat = 0
    /// Trailing icon buttons align to the same content edge as the neon inset.
    static let headerStripTrailingPadding: CGFloat = 0

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

    // MARK: - Contrast (unit tests)

    enum ContrastMetrics {
        static let panelBackgroundSRGB = (r: 0.0, g: 0.0, b: 0.0)
        static let completedShadedSRGB = (r: 24.0 / 255.0, g: 72.0 / 255.0, b: 78.0 / 255.0)
        static let readableMutedCyanSRGB = (r: 61.0 / 255.0, g: 150.0 / 255.0, b: 164.0 / 255.0)
        static let minimumReadableContrastRatio = 4.5

        static func wcagContrastRatio(
            foreground: (r: Double, g: Double, b: Double),
            background: (r: Double, g: Double, b: Double)
        ) -> Double {
            let l1 = relativeLuminance(foreground)
            let l2 = relativeLuminance(background)
            let lighter = max(l1, l2)
            let darker = min(l1, l2)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private static func relativeLuminance(_ srgb: (r: Double, g: Double, b: Double)) -> Double {
            func channel(_ value: Double) -> Double {
                if value <= 0.03928 {
                    return value / 12.92
                }
                return pow((value + 0.055) / 1.055, 2.4)
            }
            let r = channel(srgb.r)
            let g = channel(srgb.g)
            let b = channel(srgb.b)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
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
            .ignoresSafeArea(.container, edges: .top)
            .padding(contentInset)
            .background {
                SmokedGlassFill(
                    material: .hudWindow,
                    smokeOpacity: 0.38,
                    topChromeVeilOpacity: CyberpunkTheme.windowTopChromeVeilOpacity,
                    topChromeVeilHeight: CyberpunkTheme.windowTopChromeVeilHeight
                )
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
    @EnvironmentObject private var settings: AkashicSettingsStore
    @ViewBuilder var trailing: () -> Trailing

    init(@ViewBuilder trailing: @escaping () -> Trailing) {
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            // Logo slot is centered in the window (ZStack), not in the gap
            // between unequal side zones. Stats and buttons sit in fixed-width
            // side zones, so toggling stats/logo never moves anything.
            ZStack {
                Group {
                    if settings.showAkashicLogo {
                        AkashicHeaderWordmarkView()
                            .offset(y: CyberpunkTheme.headerWordmarkVerticalOffset)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: HeaderAppearanceLayout.centerZoneWidth, height: CyberpunkTheme.headerWordmarkHeight)
                .allowsHitTesting(false)

                HStack(alignment: .center, spacing: 0) {
                    HeaderMetricsStrip()
                        .frame(width: HeaderAppearanceLayout.leftZoneWidth, alignment: .leading)

                    Spacer(minLength: 8)
                        .allowsHitTesting(false)

                    trailing()
                        .frame(minWidth: HeaderAppearanceLayout.rightZoneWidth, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, CyberpunkTheme.headerStripLeadingPadding)
            .padding(.trailing, CyberpunkTheme.headerStripTrailingPadding)
            .padding(.vertical, CyberpunkTheme.headerStripVerticalPadding)
            .background(WindowDragRegion())
            Rectangle()
                .fill(CyberpunkTheme.neonCyan)
                .frame(height: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.5), radius: 4)
        }
        .background(Color.black.opacity(0.18))
        .ignoresSafeArea(.container, edges: .top)
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

/// Fixed square chrome for header icon buttons (Add, sidebar toggles).
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
