import SwiftUI
import Combine

/// Persisted main-window todo list (left column) visibility.
@MainActor
final class SidebarVisibilityStore: ObservableObject {
    private static let defaultsKey = "akashic.mainWindow.sidebarVisible"

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
        isVisible ? "Hide Sidebar" : "Show Sidebar"
    }
}
