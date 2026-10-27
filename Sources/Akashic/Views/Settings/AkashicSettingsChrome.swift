import AppKit
import SwiftUI

enum AkashicSettingsChrome {
    static let accent = CyberpunkTheme.neonCyan
    static let label = Color(white: 0.56)
    static let windowChamfer: CGFloat = 18
    static let minimumSize = NSSize(width: 520, height: 420)
    private static let sizeKey = "akashic.settingsPanelSize"

    static func initialSize(in visible: NSRect) -> NSSize {
        var size = NSSize(
            width: min(max(visible.width * 0.55, 560), 720),
            height: min(max(visible.height * 0.62, 480), 640)
        )
        if let saved = UserDefaults.standard.string(forKey: sizeKey) {
            let restored = NSSizeFromString(saved)
            if restored.width > 0, restored.height > 0 { size = restored }
        }
        size.width = min(max(size.width, minimumSize.width), visible.width)
        size.height = min(max(size.height, minimumSize.height), visible.height)
        return size
    }

    static func remember(size: NSSize) {
        UserDefaults.standard.set(NSStringFromSize(size), forKey: sizeKey)
    }

    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("Menlo", size: size).weight(bold ? .bold : .regular)
    }
}

struct AkashicSettingsButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AkashicSettingsChrome.font(11, bold: true))
                .foregroundStyle(AkashicSettingsChrome.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Rectangle().fill(Color.black.opacity(hovering ? 0.5 : 0.35)))
                .overlay(
                    Rectangle()
                        .stroke(AkashicSettingsChrome.accent.opacity(hovering ? 1 : 0.5), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .akashicSettingsFocusRing()
    }
}

final class AkashicSettingsChamferedEffectView: NSVisualEffectView {
    override func layout() {
        super.layout()
        let cut = AkashicSettingsChrome.windowChamfer
        let width = bounds.width
        let height = bounds.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width - cut, y: 0))
        path.addLine(to: CGPoint(x: width, y: cut))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        let mask = CAShapeLayer()
        mask.path = path
        layer?.mask = mask
    }
}
