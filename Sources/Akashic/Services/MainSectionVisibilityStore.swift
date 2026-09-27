import SwiftUI
import Combine

/// Persisted main-window editor (right column) visibility.
@MainActor
final class MainSectionVisibilityStore: ObservableObject {
    private static let defaultsKey = "akashic.mainWindow.mainSectionVisible"

    @Published var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.defaultsKey)
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            isVisible = true
        } else {
            isVisible = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        }
    }

    func toggle() {
        isVisible.toggle()
    }

    var toggleMenuTitle: String {
        isVisible ? "Hide Editor" : "Show Editor"
    }

    var headerTooltip: String {
        isVisible ? "Hide editor (⌘⌥E)" : "Show editor (⌘⌥E)"
    }
}
