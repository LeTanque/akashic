import AkashicCore
import SwiftUI

extension AkashicTagColor {
    public var swiftUIColor: Color {
        switch self {
        case .cyan:
            CyberpunkTheme.neonCyan
        case .electricBlue:
            Color(red: 0.2, green: 0.55, blue: 1)
        case .orange:
            CyberpunkTheme.neonOrange
        case .magenta:
            Color(red: 1, green: 0.2, blue: 0.75)
        case .purple:
            Color(red: 0.65, green: 0.35, blue: 1)
        case .green:
            Color(red: 0.2, green: 0.95, blue: 0.45)
        case .yellow:
            Color(red: 1, green: 0.92, blue: 0.2)
        case .red:
            Color(red: 1, green: 0.28, blue: 0.28)
        case .gray:
            Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}
