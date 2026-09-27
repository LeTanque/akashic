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
        XCTAssertEqual(
            CompactBytes.freeOverUsed(
                free: 64 * 1024 * 1024 * 1024,
                used: 392 * 1024 * 1024 * 1024
            ),
            "64/392G"
        )
    }

    func testStripTextMatchesHeaderPattern() {
        let lines = MetricsStripText.make(
            diskFree: 64 * 1024 * 1024 * 1024,
            diskUsed: 392 * 1024 * 1024 * 1024,
            sysUsed: 18 * 1024 * 1024 * 1024,
            sysTotal: 36 * 1024 * 1024 * 1024,
            cpuPercent: 23.4,
            cursorIncludedRemainingUSD: 42.5,
            cursorBonusSpendUSD: nil,
            cursorModelsUsedPercent: 21,
            otherModelsUsedPercent: 7,
            grokBotRemainingPercent: 88
        )
        XCTAssertEqual(lines.full.top, "DISK 64/392G  ·  SYS 18/36G  ·  CPU 23%")
        XCTAssertEqual(lines.full.bottom, "$43  ·  CM 21%  ·  OM 7%  ·  BOT 88%")
        XCTAssertEqual(lines.tight.top, "DISK 64/392G · SYS 18/36G · CPU 23%")
        XCTAssertEqual(lines.tight.bottom, "$43 · CM 21% · OM 7% · BOT 88%")
        XCTAssertTrue(lines.spoken.contains("Cursor Models 21 percent used"))
        XCTAssertTrue(lines.spoken.contains("Grok Bot weekly 88 percent remaining"))
        XCTAssertTrue(lines.spoken.contains("$43 included spend remaining"))
    }

    func testStripTextEmptyStatesAndBeyondIncluded() {
        let lines = MetricsStripText.make(
            diskFree: 128 * 1024 * 1024 * 1024,
            diskUsed: 800 * 1024 * 1024 * 1024,
            sysUsed: 4 * 1024 * 1024 * 1024,
            sysTotal: 8 * 1024 * 1024 * 1024,
            cpuPercent: nil,
            cursorIncludedRemainingUSD: 0,
            cursorBonusSpendUSD: 5.25,
            cursorModelsUsedPercent: nil,
            otherModelsUsedPercent: nil,
            grokBotRemainingPercent: nil
        )
        XCTAssertEqual(lines.full.top, "DISK 128/800G  ·  SYS 4/8G  ·  CPU —")
        XCTAssertEqual(lines.full.bottom, "$0 +$5  ·  CM —  ·  OM —  ·  BOT —")
        XCTAssertTrue(lines.spoken.contains("Cursor Models unavailable"))
        XCTAssertTrue(lines.spoken.contains("beyond included"))
    }

    func testCursorQuotaPercentParsing() {
        XCTAssertEqual(CursorDashboardQuotaClient.percentUsed(21.4), 21.4)
        XCTAssertEqual(CursorDashboardQuotaClient.percentUsed(0.21), 21, accuracy: 0.001)
        XCTAssertEqual(CursorDashboardQuotaClient.percentUsed(1), 100)
        XCTAssertNil(CursorDashboardQuotaClient.percentUsed(nil))
    }

    func testCursorSessionAuthExtractsUserIDFromJWT() {
        func base64URL(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let piped = base64URL(#"{"sub":"prefix|myUserId|suffix"}"#)
        XCTAssertEqual(CursorSessionAuth.userID(fromJWT: "hdr.\(piped).sig"), "myUserId")

        let solo = base64URL(#"{"sub":"user_only"}"#)
        XCTAssertEqual(CursorSessionAuth.userID(fromJWT: "hdr.\(solo).sig"), "user_only")
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

    func testCPUDeltaIsMachineWidePercent() {
        let previous = HostCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = HostCPUTicks(user: 180, system: 70, idle: 950, nice: 0)
        XCTAssertEqual(current.usagePercent(since: previous), 50)
    }
}
