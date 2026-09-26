import XCTest
@testable import Akashic

@MainActor
final class LiveMetricsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AgentMetricsStore.shared.resetForTesting()
    }

    override func tearDown() {
        AgentMetricsStore.shared.resetForTesting()
        super.tearDown()
    }

    func testCompactBytesUsesShortUnits() {
        XCTAssertEqual(CompactBytes.format(512), "0.5K")
        XCTAssertEqual(CompactBytes.format(42 * 1024 * 1024), "42M")
        XCTAssertEqual(CompactBytes.format(UInt64(1.2 * 1024 * 1024 * 1024)), "1.2G")
        XCTAssertEqual(
            CompactBytes.usedOverTotal(used: 18 * 1024 * 1024 * 1024, total: 36 * 1024 * 1024 * 1024),
            "18/36G"
        )
    }

    func testStripTextMatchesHeaderPattern() {
        let lines = MetricsStripText.make(
            appRSS: 42 * 1024 * 1024,
            sysUsed: 18 * 1024 * 1024 * 1024,
            sysTotal: 36 * 1024 * 1024 * 1024,
            cpuPercent: 23.4,
            cloudAgents: 2,
            bots: nil
        )
        XCTAssertEqual(lines.full, "APP 42M  ·  SYS 18/36G  ·  CPU 23%  ·  CA 2")
        XCTAssertEqual(lines.compact, "APP 42M  ·  CPU 23%  ·  CA 2")
        XCTAssertEqual(lines.short, "APP 42M  ·  CA 2")
        XCTAssertEqual(lines.minimal, "APP 42M")
    }

    func testStripTextEmptyStatesAndOptionalBot() {
        let lines = MetricsStripText.make(
            appRSS: 8 * 1024 * 1024,
            sysUsed: 4 * 1024 * 1024 * 1024,
            sysTotal: 8 * 1024 * 1024 * 1024,
            cpuPercent: nil,
            cloudAgents: nil,
            bots: 1
        )
        XCTAssertEqual(lines.full, "APP 8M  ·  SYS 4/8G  ·  CPU —  ·  CA —  ·  BOT 1")
        XCTAssertEqual(lines.compact, "APP 8M  ·  CPU —  ·  CA —  ·  BOT 1")
    }

    func testParseAgentMetricsSamplePayload() throws {
        let json = """
        {
          "activeCloudAgents": 2,
          "runningCloudAgents": [
            {"id": "bc-example", "title": "short title", "status": "running"}
          ],
          "activeBots": null,
          "updatedAt": "2026-09-26T02:31:00Z"
        }
        """.data(using: .utf8)!
        let payload = try AgentMetricsPayload.parse(json).get()
        XCTAssertEqual(payload.activeCloudAgents, 2)
        XCTAssertEqual(payload.runningCloudAgents.count, 1)
        XCTAssertEqual(payload.runningCloudAgents.first?.id, "bc-example")
        XCTAssertNil(payload.activeBots)
        let expected = try XCTUnwrap(ISO8601JSON.parse("2026-09-26T02:31:00Z"))
        XCTAssertEqual(payload.updatedAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testParseRejectsNegativeAndMissingFields() {
        let missing = #"{ "updatedAt": "2026-09-26T02:31:00Z" }"#.data(using: .utf8)!
        XCTAssertEqual(AgentMetricsPayload.parse(missing), .failure(.missingActiveCloudAgents))

        let negative = #"{ "activeCloudAgents": -1, "updatedAt": "2026-09-26T02:31:00Z" }"#.data(using: .utf8)!
        XCTAssertEqual(AgentMetricsPayload.parse(negative), .failure(.negativeActiveCloudAgents))

        let badDate = #"{ "activeCloudAgents": 1, "updatedAt": "not-a-date" }"#.data(using: .utf8)!
        XCTAssertEqual(AgentMetricsPayload.parse(badDate), .failure(.invalidUpdatedAt))
    }

    func testRecentZeroIsShownAndStaleFeedIsEmpty() {
        let store = AgentMetricsStore.shared
        let now = Date()

        store.replace(
            AgentMetricsPayload(
                activeCloudAgents: 0,
                runningCloudAgents: [],
                activeBots: nil,
                updatedAt: now
            )
        )
        XCTAssertEqual(store.displayedCloudAgentCount(at: now), 0)

        store.replace(
            AgentMetricsPayload(
                activeCloudAgents: 2,
                runningCloudAgents: [],
                activeBots: 3,
                updatedAt: now.addingTimeInterval(-AgentMetricsStore.staleAfter)
            )
        )
        XCTAssertNil(store.displayedCloudAgentCount(at: now))
        XCTAssertNil(store.displayedBotCount(at: now))

        // 5-minute Grok Bot interval is still inside the ~7-minute window.
        store.replace(
            AgentMetricsPayload(
                activeCloudAgents: 2,
                runningCloudAgents: [],
                activeBots: 3,
                updatedAt: now.addingTimeInterval(-5 * 60)
            )
        )
        XCTAssertEqual(store.displayedCloudAgentCount(at: now), 2)
        XCTAssertEqual(store.displayedBotCount(at: now), 3)

        store.replace(
            AgentMetricsPayload(
                activeCloudAgents: 2,
                runningCloudAgents: [],
                activeBots: 3,
                updatedAt: now.addingTimeInterval(-(AgentMetricsStore.staleAfter - 1))
            )
        )
        XCTAssertEqual(store.displayedCloudAgentCount(at: now), 2)
        XCTAssertEqual(store.displayedBotCount(at: now), 3)

        store.resetForTesting()
        XCTAssertNil(store.displayedCloudAgentCount(at: now))
    }

    func testCPUDeltaIsMachineWidePercent() {
        let previous = HostCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = HostCPUTicks(user: 180, system: 70, idle: 950, nice: 0)
        // busy +100, total +200 → 50%
        XCTAssertEqual(current.usagePercent(since: previous), 50)
    }
}
