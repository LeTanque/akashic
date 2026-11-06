import XCTest
@testable import AkashicCore

final class HybridLogicalClockTests: XCTestCase {
    func testTickMonotonicWithinProcess() {
        let d1 = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let src = HybridLogicalClockSource(deviceId: d1)
        let a = src.tick()
        let b = src.tick()
        XCTAssertLessThan(a, b)
    }

    func testReceiveAdvancesPastRemote() {
        let localId = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let remoteId = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let src = HybridLogicalClockSource(deviceId: localId)
        _ = src.tick()
        let remote = HybridLogicalClock(wallMillis: 9_999_999_999, counter: 42, deviceId: remoteId)
        src.receive(remote)
        let after = src.tick()
        XCTAssertGreaterThanOrEqual(after.wallMillis, remote.wallMillis)
    }
}
