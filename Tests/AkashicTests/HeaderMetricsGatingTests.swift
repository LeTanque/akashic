import XCTest
@testable import Akashic

final class HeaderMetricsGatingTests: XCTestCase {
    func testLiveMetricsSubviewOnlyMountsWhenEnabled() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/HeaderMetricsStrip.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("HeaderMetricsStripLive"))
        XCTAssertTrue(source.contains("MetricsMonitoringLifecycle.shouldMonitor"))
        XCTAssertTrue(source.contains("@StateObject private var live = LiveMetricsMonitor()"))
        guard let liveRange = source.range(of: "private struct HeaderMetricsStripLive") else {
            return XCTFail("HeaderMetricsStripLive missing")
        }
        let liveBlock = String(source[liveRange.lowerBound...].prefix(2400))
        XCTAssertTrue(liveBlock.contains("CursorQuotaMonitor"))
        XCTAssertTrue(liveBlock.contains("live.start()"))
        XCTAssertTrue(liveBlock.contains("cursorQuota.start()"))
        XCTAssertTrue(liveBlock.contains("live.stop()"))
        XCTAssertTrue(liveBlock.contains("cursorQuota.stop()"))
    }
}
