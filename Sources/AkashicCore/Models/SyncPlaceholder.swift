import Foundation

public enum SyncPlaceholder {
    /// Placeholder device id for in-memory drafts not yet persisted (replaced on insert).
    public static let draftDeviceId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static var draftHLC: HybridLogicalClock {
        HybridLogicalClock(wallMillis: 0, counter: 0, deviceId: draftDeviceId)
    }
}
