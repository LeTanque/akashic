import XCTest
@testable import Akashic

@MainActor
final class AkashicSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "akashic.settings.tests.\(UUID().uuidString)"
        // In-memory so test runs never write akashic.settings.tests.*.plist
        // files into ~/Library/Preferences.
        defaults = InMemoryUserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchExistingUserExpectations() {
        let store = AkashicSettingsStore(defaults: defaults)
        XCTAssertEqual(store.menuBarSymbolName, AkashicSettingsStore.defaultMenuBarSymbol)
        XCTAssertTrue(store.showSystemInformation)
        XCTAssertTrue(store.showAkashicLogo)
        XCTAssertFalse(store.showInDockAndAppSwitcher)
    }

    func testPersistenceRoundTrip() {
        let store = AkashicSettingsStore(defaults: defaults)
        store.menuBarSymbolName = "bolt.fill"
        store.showSystemInformation = false
        store.showAkashicLogo = false
        store.showInDockAndAppSwitcher = true

        let reloaded = AkashicSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarSymbolName, "bolt.fill")
        XCTAssertFalse(reloaded.showSystemInformation)
        XCTAssertFalse(reloaded.showAkashicLogo)
        XCTAssertTrue(reloaded.showInDockAndAppSwitcher)
    }

    func testUnknownMenuBarSymbolFallsBackToSparkles() {
        defaults.set("not.a.real.symbol", forKey: "akashic.settings.menuBarSymbol")
        let store = AkashicSettingsStore(defaults: defaults)
        XCTAssertEqual(store.menuBarSymbolName, AkashicSettingsStore.defaultMenuBarSymbol)
    }

    func testMetricsMonitoringLifecycleGate() {
        XCTAssertTrue(MetricsMonitoringLifecycle.shouldMonitor(showSystemInformation: true))
        XCTAssertFalse(MetricsMonitoringLifecycle.shouldMonitor(showSystemInformation: false))
    }

    func testHeaderZoneWidthsAreFixed() {
        XCTAssertGreaterThan(HeaderAppearanceLayout.leftZoneWidth, 200)
        XCTAssertGreaterThan(HeaderAppearanceLayout.centerZoneWidth, 100)
        XCTAssertGreaterThan(HeaderAppearanceLayout.rightZoneWidth, 80)
    }
}

/// UserDefaults that never touches cfprefsd/disk; covers the accessors AkashicSettingsStore uses.
private final class InMemoryUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { storage[defaultName] }
    override func string(forKey defaultName: String) -> String? { storage[defaultName] as? String }
    override func bool(forKey defaultName: String) -> Bool { (storage[defaultName] as? Bool) ?? false }
    override func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { storage[defaultName] = value }
    override func removeObject(forKey defaultName: String) { storage[defaultName] = nil }
    override func removePersistentDomain(forName domainName: String) { storage.removeAll() }
}
