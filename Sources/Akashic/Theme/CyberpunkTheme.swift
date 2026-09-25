import SwiftUI

enum CyberpunkTheme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.08)
    static let panel = Color(red: 0.08, green: 0.09, blue: 0.14)
    static let neonCyan = Color(red: 0, green: 0.94, blue: 1)
    static let neonMagenta = Color(red: 1, green: 0, blue: 0.67)
    static let neonGreen = Color(red: 0.2, green: 1, blue: 0.55)
    static let textPrimary = Color(red: 0.92, green: 0.94, blue: 0.98)
    static let textSecondary = Color(red: 0.55, green: 0.58, blue: 0.68)
    static let border = Color.white.opacity(0.12)

    static func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high: neonMagenta
        case .medium: neonCyan
        case .low: textSecondary
        }
    }
}
