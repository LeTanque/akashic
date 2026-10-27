import XCTest
@testable import Akashic

@MainActor
final class AkashicSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "akashic.settings.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchExistingUserExpectations() {
        let store = AkashicSettingsStore(defaults: defaults)
        XCTAssertEqual(store.menuBarSymbolName, AkashicSettingsStore.defaultMenuBarSymbol)
        XCTAssertTrue(store.showSystemInformation)
        XCTAssertTrue(store.showAkashicLogo)
    }

    func testPersistenceRoundTrip() {
        let store = AkashicSettingsStore(defaults: defaults)
        store.menuBarSymbolName = "bolt.fill"
        store.showSystemInformation = false
        store.showAkashicLogo = false

        let reloaded = AkashicSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarSymbolName, "bolt.fill")
        XCTAssertFalse(reloaded.showSystemInformation)
        XCTAssertFalse(reloaded.showAkashicLogo)
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
