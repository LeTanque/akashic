import XCTest
@testable import Akashic

@MainActor
final class MainSectionVisibilityStoreTests: XCTestCase {
    private let defaultsKey = "akashic.mainWindow.mainSectionVisible"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    func testDefaultsToVisibleWhenUnset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let store = MainSectionVisibilityStore()
        XCTAssertTrue(store.isVisible)
    }

    func testToggleUpdatesVisibility() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        let store = MainSectionVisibilityStore()
        XCTAssertFalse(store.isVisible)
        store.toggle()
        XCTAssertTrue(store.isVisible)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: defaultsKey))
    }

    func testToggleMenuTitleReflectsState() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let store = MainSectionVisibilityStore()
        XCTAssertEqual(store.toggleMenuTitle, "Hide Editor")
        store.isVisible = false
        XCTAssertEqual(store.toggleMenuTitle, "Show Editor")
    }
}
