import Foundation

/// Serialized scalar values for merge (deterministic equality).
public enum ScalarPayload: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case dateMillis(Int64?) /// UTC millis; nil encodes as absent optional
}

/// Portable merge input/output (no GRDB).
public struct MergeSnapshot: Equatable, Sendable {
    public var entity: SyncEntity
    public var recordId: String
    public var textFields: [String: (value: String, clock: HybridLogicalClock)]
    public var scalars: [String: (value: ScalarPayload, clock: HybridLogicalClock)]
    public var deletedAt: Date?
    public var deleteClock: HybridLogicalClock?
    public var recordHLC: HybridLogicalClock
    public var version: VersionVector

    public init(
        entity: SyncEntity,
        recordId: String,
        textFields: [String: (value: String, clock: HybridLogicalClock)],
        scalars: [String: (value: ScalarPayload, clock: HybridLogicalClock)],
        deletedAt: Date?,
        deleteClock: HybridLogicalClock?,
        recordHLC: HybridLogicalClock,
        version: VersionVector
    ) {
        self.entity = entity
        self.recordId = recordId
        self.textFields = textFields
        self.scalars = scalars
        self.deletedAt = deletedAt
        self.deleteClock = deleteClock
        self.recordHLC = recordHLC
        self.version = version
    }
}

public enum RecordMerge {
    public static func shortDeviceLabel(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    public static func mergedSeparator(deviceId: UUID) -> String {
        "\n\n— merged from \(shortDeviceLabel(deviceId)) —\n\n"
    }

    /// Field-level merge with LWW scalars, concat on concurrent text divergence, edit-beats-delete.
    public static func mergeRecord(local: MergeSnapshot, remote: MergeSnapshot) -> MergeSnapshot {
        precondition(local.entity == remote.entity && local.recordId == remote.recordId)

        let mergedVV = VersionVector.merged(local.version, remote.version)
        let localDescRemote = VersionVector.descends(from: local.version, to: remote.version)
        let remoteDescLocal = VersionVector.descends(from: remote.version, to: local.version)

        var textOut: [String: (String, HybridLogicalClock)] = [:]
        let textKeys = Set(local.textFields.keys).union(remote.textFields.keys)
        for key in textKeys.sorted() {
            let lv = local.textFields[key]
            let rv = remote.textFields[key]
            switch (lv, rv) {
            case (nil, let r?):
                textOut[key] = r
            case (let l?, nil):
                textOut[key] = l
            case (let l?, let r?):
                textOut[key] = mergeTextPair(
                    key: key,
                    local: l,
                    remote: r,
                    localDescRemote: localDescRemote,
                    remoteDescLocal: remoteDescLocal,
                    mergedVV: mergedVV
                )
            case (nil, nil):
                break
            }
        }

        var scalarOut: [String: (ScalarPayload, HybridLogicalClock)] = [:]
        let scalarKeys = Set(local.scalars.keys).union(remote.scalars.keys)
        for key in scalarKeys.sorted() {
            let lv = local.scalars[key]
            let rv = remote.scalars[key]
            switch (lv, rv) {
            case (nil, let r?):
                scalarOut[key] = r
            case (let l?, nil):
                scalarOut[key] = l
            case (let l?, let r?):
                scalarOut[key] = l.value == r.value ? (l.value, maxHLC(l.clock, r.clock)) : (l.clock > r.clock ? l : r)
            case (nil, nil):
                break
            }
        }

        let tombstoneLocal = local.deletedAt != nil
        let tombstoneRemote = remote.deletedAt != nil

        var outDeleted: Date?
        var outDeleteClock: HybridLogicalClock?

        if !tombstoneLocal && !tombstoneRemote {
            outDeleted = nil
            outDeleteClock = nil
        } else if tombstoneLocal && !tombstoneRemote {
            let resurrection = shouldResurrect(
                tombstone: local,
                live: remote,
                liveDescendsTomb: remoteDescLocal
            )
            if resurrection {
                outDeleted = nil
                outDeleteClock = nil
            } else {
                outDeleted = local.deletedAt
                outDeleteClock = local.deleteClock ?? local.recordHLC
            }
        } else if !tombstoneLocal && tombstoneRemote {
            let resurrection = shouldResurrect(
                tombstone: remote,
                live: local,
                liveDescendsTomb: localDescRemote
            )
            if resurrection {
                outDeleted = nil
                outDeleteClock = nil
            } else {
                outDeleted = remote.deletedAt
                outDeleteClock = remote.deleteClock ?? remote.recordHLC
            }
        } else {
            let l = local.deletedAt ?? .distantPast
            let r = remote.deletedAt ?? .distantPast
            outDeleted = l >= r ? local.deletedAt : remote.deletedAt
            outDeleteClock = maxHLC(local.deleteClock ?? local.recordHLC, remote.deleteClock ?? remote.recordHLC)
        }

        let recordHLC = maxHLC(local.recordHLC, remote.recordHLC)

        return MergeSnapshot(
            entity: local.entity,
            recordId: local.recordId,
            textFields: textOut,
            scalars: scalarOut,
            deletedAt: outDeleted,
            deleteClock: outDeleteClock,
            recordHLC: recordHLC,
            version: mergedVV
        )
    }

    private static func shouldResurrect(
        tombstone: MergeSnapshot,
        live: MergeSnapshot,
        liveDescendsTomb: Bool
    ) -> Bool {
        let delClock = tombstone.deleteClock ?? tombstone.recordHLC
        let contentClock = maxContentClock(live)
        if liveDescendsTomb { return true }
        if contentClock > delClock { return true }
        return false
    }

    private static func maxContentClock(_ s: MergeSnapshot) -> HybridLogicalClock {
        var best = s.recordHLC
        for (_, pair) in s.textFields {
            if pair.clock > best { best = pair.clock }
        }
        for (_, pair) in s.scalars {
            if pair.clock > best { best = pair.clock }
        }
        return best
    }

    private static func mergeTextPair(
        key: String,
        local: (value: String, clock: HybridLogicalClock),
        remote: (value: String, clock: HybridLogicalClock),
        localDescRemote: Bool,
        remoteDescLocal: Bool,
        mergedVV: VersionVector
    ) -> (String, HybridLogicalClock) {
        if local.value == remote.value {
            return (local.value, maxHLC(local.clock, remote.clock))
        }
        if localDescRemote, !remoteDescLocal {
            return remote
        }
        if remoteDescLocal, !localDescRemote {
            return local
        }
        let pair = concurrentTextMerge(local: local, remote: remote)
        _ = key
        _ = mergedVV
        return pair
    }

    private static func concurrentTextMerge(
        local: (value: String, clock: HybridLogicalClock),
        remote: (value: String, clock: HybridLogicalClock)
    ) -> (String, HybridLogicalClock) {
        let firstIsLocal = local.clock < remote.clock || (local.clock == remote.clock && local.clock.deviceId.uuidString < remote.clock.deviceId.uuidString)
        let (first, second) = firstIsLocal ? (local, remote) : (remote, local)
        let mergedText = first.value + mergedSeparator(deviceId: second.clock.deviceId) + second.value
        let mergedClock = maxHLC(first.clock, second.clock)
        return (mergedText, mergedClock)
    }

    private static func maxHLC(_ a: HybridLogicalClock, _ b: HybridLogicalClock) -> HybridLogicalClock {
        a > b ? a : b
    }
}

// MARK: - Model bridges (pure)

extension TodoItem {
    public func mergeSnapshot() -> MergeSnapshot {
        let tid = id.uuidString
        var text: [String: (String, HybridLogicalClock)] = [:]
        text["title"] = (title, fieldClocks["title"] ?? hlc)
        text["description"] = (description, fieldClocks["description"] ?? hlc)

        var scalars: [String: (ScalarPayload, HybridLogicalClock)] = [:]
        scalars["completed"] = (.bool(completed), fieldClocks["completed"] ?? hlc)
        scalars["priority"] = (.string(priority.rawValue), fieldClocks["priority"] ?? hlc)
        scalars["sort_order"] = (.int(sortOrder), fieldClocks["sort_order"] ?? hlc)
        scalars["complete_by"] = (.dateMillis(completeBy.map { Int64($0.timeIntervalSince1970 * 1000) }), fieldClocks["complete_by"] ?? hlc)
        scalars["completed_at"] = (.dateMillis(completedAt.map { Int64($0.timeIntervalSince1970 * 1000) }), fieldClocks["completed_at"] ?? hlc)

        let delClock = fieldClocks["deleted_at"]
        return MergeSnapshot(
            entity: .todo,
            recordId: tid,
            textFields: text,
            scalars: scalars,
            deletedAt: deletedAt,
            deleteClock: delClock,
            recordHLC: hlc,
            version: version
        )
    }

    public mutating func applyMergeSnapshot(_ m: MergeSnapshot) {
        title = m.textFields["title"]?.value ?? title
        description = m.textFields["description"]?.value ?? description
        if let c = m.scalars["completed"]?.value, case .bool(let b) = c { completed = b }
        if let p = m.scalars["priority"]?.value, case .string(let s) = p, let pr = TodoPriority(rawValue: s) { priority = pr }
        if let s = m.scalars["sort_order"]?.value, case .int(let i) = s { sortOrder = i }
        if let d = m.scalars["complete_by"]?.value, case .dateMillis(let ms) = d {
            completeBy = ms.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        }
        if let d = m.scalars["completed_at"]?.value, case .dateMillis(let ms) = d {
            completedAt = ms.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        }
        deletedAt = m.deletedAt
        hlc = m.recordHLC
        version = m.version
        var fc = FieldClockMap()
        for (k, v) in m.textFields { fc.set(v.clock, for: k) }
        for (k, v) in m.scalars { fc.set(v.clock, for: k) }
        if let dc = m.deleteClock { fc.set(dc, for: "deleted_at") }
        fieldClocks = fc
    }
}

extension NoteItem {
    public func mergeSnapshot() -> MergeSnapshot {
        let sid = id.uuidString
        var text: [String: (String, HybridLogicalClock)] = [:]
        text["title"] = (title, fieldClocks["title"] ?? hlc)
        text["body"] = (body, fieldClocks["body"] ?? hlc)
        let tagKeys = NoteTagNormalization.normalizeTags(tags).map(\.nameKey).sorted().joined(separator: ",")
        text["tags"] = (tagKeys, fieldClocks["tags"] ?? hlc)

        return MergeSnapshot(
            entity: .note,
            recordId: sid,
            textFields: text,
            scalars: [:],
            deletedAt: deletedAt,
            deleteClock: fieldClocks["deleted_at"],
            recordHLC: hlc,
            version: version
        )
    }

    public mutating func applyMergeSnapshot(_ m: MergeSnapshot) {
        title = m.textFields["title"]?.value ?? title
        body = m.textFields["body"]?.value ?? body
        if let tagSerialized = m.textFields["tags"]?.value {
            let keys = tagSerialized.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            tags = keys.map { AkashicTag(name: $0, color: .defaultForNewTag) }
        }
        deletedAt = m.deletedAt
        hlc = m.recordHLC
        version = m.version
        var fc = FieldClockMap()
        for (k, v) in m.textFields { fc.set(v.clock, for: k) }
        if let dc = m.deleteClock { fc.set(dc, for: "deleted_at") }
        fieldClocks = fc
    }
}
