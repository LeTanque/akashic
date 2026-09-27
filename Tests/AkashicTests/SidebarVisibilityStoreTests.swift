import XCTest
@testable import Akashic

@MainActor
final class SidebarVisibilityStoreTests: XCTestCase {
    private let defaultsKey = "akashic.mainWindow.sidebarVisible"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    func testDefaultsToVisibleWhenUnset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let store = SidebarVisibilityStore()
        XCTAssertTrue(store.isVisible)
    }

    func testToggleUpdatesVisibility() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        let store = SidebarVisibilityStore()
        XCTAssertFalse(store.isVisible)
        store.toggle()
        XCTAssertTrue(store.isVisible)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: defaultsKey))
    }

    func testToggleMenuTitleReflectsState() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let store = SidebarVisibilityStore()
        XCTAssertEqual(store.toggleMenuTitle, "Hide Sidebar")
        store.isVisible = false
        XCTAssertEqual(store.toggleMenuTitle, "Show Sidebar")
    }
}
