import SwiftUI
import Combine

/// Persisted UI text zoom for the main window and menu-bar popover.
@MainActor
final class TextZoomStore: ObservableObject {
    static let min: CGFloat = 0.8
    static let max: CGFloat = 1.6
    static let step: CGFloat = 0.1
    static let defaultScale: CGFloat = 1.0
    private static let defaultsKey = "akashic.textZoom"

    @Published private(set) var scale: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(scale), forKey: Self.defaultsKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Double
        let value = CGFloat(stored ?? Double(Self.defaultScale))
        scale = Self.clamped(value)
    }

    var percentLabel: String {
        "\(Int((scale * 100).rounded()))%"
    }

    var canZoomIn: Bool { scale < Self.max - 0.001 }
    var canZoomOut: Bool { scale > Self.min + 0.001 }

    func zoomIn() {
        scale = Self.clamped(scale + Self.step)
    }

    func zoomOut() {
        scale = Self.clamped(scale - Self.step)
    }

    func reset() {
        scale = Self.defaultScale
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        let stepped = (value / step).rounded() * step
        return Swift.min(Self.max, Swift.max(Self.min, stepped))
    }
}

private struct TextZoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textZoom: CGFloat {
        get { self[TextZoomKey.self] }
        set { self[TextZoomKey.self] = newValue }
    }
}

enum AkashicFont {
    /// Base point sizes at 100% zoom (monospaced).
    static let title: CGFloat = 18
    static let headline: CGFloat = 15
    static let body: CGFloat = 14
    static let callout: CGFloat = 13
    static let caption: CGFloat = 11
    static let caption2: CGFloat = 10
    static let micro: CGFloat = 9

    static func mono(
        _ base: CGFloat,
        weight: Font.Weight = .regular,
        zoom: CGFloat
    ) -> Font {
        .system(size: base * zoom, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Exposes `textZoom` so copy uses `AkashicFont.mono(..., zoom:)`.
    func akashicTextZoom(_ zoom: TextZoomStore) -> some View {
        environment(\.textZoom, zoom.scale)
    }
}
