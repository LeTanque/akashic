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

    public static func == (lhs: MergeSnapshot, rhs: MergeSnapshot) -> Bool {
        guard lhs.entity == rhs.entity,
              lhs.recordId == rhs.recordId,
              lhs.deletedAt == rhs.deletedAt,
              lhs.deleteClock == rhs.deleteClock,
              lhs.recordHLC == rhs.recordHLC,
              lhs.version == rhs.version,
              lhs.textFields.count == rhs.textFields.count,
              lhs.scalars.count == rhs.scalars.count
        else { return false }
        for (key, lv) in lhs.textFields {
            guard let rv = rhs.textFields[key], lv.value == rv.value, lv.clock == rv.clock else { return false }
        }
        for (key, lv) in lhs.scalars {
            guard let rv = rhs.scalars[key], lv.value == rv.value, lv.clock == rv.clock else { return false }
        }
        return true
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

    /// Associative concurrent text merge: flatten to device-keyed leaves, keep
    /// max-HLC per device, join in sorted device-id order. Every leaf is labeled
    /// so nested merges stay convergent.
    private static func concurrentTextMerge(
        local: (value: String, clock: HybridLogicalClock),
        remote: (value: String, clock: HybridLogicalClock)
    ) -> (String, HybridLogicalClock) {
        var leaves: [String: (value: String, clock: HybridLogicalClock)] = [:]
        for side in [local, remote] {
            for leaf in flattenTextLeaves(side.value, fallbackClock: side.clock) {
                let key = shortDeviceLabel(leaf.clock.deviceId).uppercased()
                if let existing = leaves[key] {
                    if leaf.clock > existing.clock { leaves[key] = leaf }
                } else {
                    leaves[key] = leaf
                }
            }
        }
        let ordered = leaves.keys.sorted().compactMap { leaves[$0] }
        precondition(!ordered.isEmpty)
        let mergedText = ordered.map { leaf in
            mergedSeparator(deviceId: leaf.clock.deviceId) + leaf.value
        }.joined()
        let trimmed = mergedText.hasPrefix("\n\n") ? String(mergedText.dropFirst(2)) : mergedText
        let mergedClock = ordered.map(\.clock).reduce(ordered[0].clock, maxHLC)
        return (trimmed, mergedClock)
    }

    private static func flattenTextLeaves(
        _ text: String,
        fallbackClock: HybridLogicalClock
    ) -> [(value: String, clock: HybridLogicalClock)] {
        let marker = "\n\n\u{2014} merged from "
        let altMarker = "\u{2014} merged from "
        if !text.contains(marker) && !text.hasPrefix(altMarker) {
            return [(text, fallbackClock)]
        }
        var result: [(String, HybridLogicalClock)] = []
        var remaining = text
        if remaining.hasPrefix(altMarker) {
            remaining = "\n\n" + remaining
        }
        let sepTail = " \u{2014}\n\n"
        while let start = remaining.range(of: marker) {
            remaining = String(remaining[start.upperBound...])
            guard remaining.count >= 8 else { break }
            let label = String(remaining.prefix(8))
            remaining = String(remaining.dropFirst(8))
            guard remaining.hasPrefix(sepTail) else { break }
            remaining = String(remaining.dropFirst(sepTail.count))
            let next = remaining.range(of: marker)
            let body = next.map { String(remaining[..<$0.lowerBound]) } ?? remaining
            if let next {
                remaining = String(remaining[next.lowerBound...])
            } else {
                remaining = ""
            }
            let device = deviceId(fromShortLabel: label, fallback: fallbackClock.deviceId)
            let leafClock: HybridLogicalClock
            if shortDeviceLabel(fallbackClock.deviceId).uppercased() == label.uppercased() {
                leafClock = fallbackClock
            } else {
                leafClock = HybridLogicalClock(
                    wallMillis: fallbackClock.wallMillis,
                    counter: fallbackClock.counter,
                    deviceId: device
                )
            }
            result.append((body, leafClock))
            if remaining.isEmpty { break }
        }
        return result.isEmpty ? [(text, fallbackClock)] : result
    }

    private static func deviceId(fromShortLabel label: String, fallback: UUID) -> UUID {
        let hex = label.lowercased()
        let padded = String((hex + String(repeating: "0", count: 32)).prefix(32))
        let chars = Array(padded)
        let s = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: s) ?? fallback
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
