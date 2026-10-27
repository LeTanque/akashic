import Combine
import SwiftUI

/// User-facing appearance and header preferences (persisted in UserDefaults).
@MainActor
final class AkashicSettingsStore: ObservableObject {
    static let defaultMenuBarSymbol = "sparkles"

    private static let menuBarSymbolKey = "akashic.settings.menuBarSymbol"
    private static let showSystemInformationKey = "akashic.settings.showSystemInformation"
    private static let showAkashicLogoKey = "akashic.settings.showAkashicLogo"

    /// SF Symbol names offered in Settings → Appearance.
    static let menuBarSymbolChoices: [String] = [
        "sparkles",
        "checklist",
        "star.fill",
        "bolt.fill",
        "moon.stars.fill",
        "cpu",
        "terminal.fill",
        "book.fill",
        "flame.fill",
        "hexagon.fill",
    ]

    @Published var menuBarSymbolName: String {
        didSet {
            let normalized = Self.normalizedSymbol(menuBarSymbolName)
            if normalized != menuBarSymbolName {
                menuBarSymbolName = normalized
                return
            }
            defaults.set(normalized, forKey: Self.menuBarSymbolKey)
        }
    }

    @Published var showSystemInformation: Bool {
        didSet {
            defaults.set(showSystemInformation, forKey: Self.showSystemInformationKey)
        }
    }

    @Published var showAkashicLogo: Bool {
        didSet {
            defaults.set(showAkashicLogo, forKey: Self.showAkashicLogoKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.menuBarSymbolKey) {
            menuBarSymbolName = Self.normalizedSymbol(saved)
        } else {
            menuBarSymbolName = Self.defaultMenuBarSymbol
        }

        if defaults.object(forKey: Self.showSystemInformationKey) == nil {
            showSystemInformation = true
        } else {
            showSystemInformation = defaults.bool(forKey: Self.showSystemInformationKey)
        }

        if defaults.object(forKey: Self.showAkashicLogoKey) == nil {
            showAkashicLogo = true
        } else {
            showAkashicLogo = defaults.bool(forKey: Self.showAkashicLogoKey)
        }
    }

    static func normalizedSymbol(_ name: String) -> String {
        menuBarSymbolChoices.contains(name) ? name : defaultMenuBarSymbol
    }
}

/// Pure gate for live machine metrics and Cursor / agent quota polling.
enum MetricsMonitoringLifecycle {
    static func shouldMonitor(showSystemInformation: Bool) -> Bool {
        showSystemInformation
    }
}

/// Fixed header column widths so toggling stats/logo does not reflow chrome.
enum HeaderAppearanceLayout {
    static let leftZoneWidth: CGFloat = 340
    static let centerZoneWidth: CGFloat = 220
    static let rightZoneWidth: CGFloat = 96
}
