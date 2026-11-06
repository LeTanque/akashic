import XCTest
@testable import AkashicCore

final class RecordMergeTests: XCTestCase {
    private let dA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let dB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let dC = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    private func hlc(_ ms: UInt64, _ c: UInt32, _ d: UUID) -> HybridLogicalClock {
        HybridLogicalClock(wallMillis: ms, counter: c, deviceId: d)
    }

    private func snapTodo(
        title: String,
        description: String,
        titleClock: HybridLogicalClock,
        descClock: HybridLogicalClock,
        version: VersionVector,
        recordHLC: HybridLogicalClock
    ) -> MergeSnapshot {
        MergeSnapshot(
            entity: .todo,
            recordId: "same-id",
            textFields: [
                "title": (title, titleClock),
                "description": (description, descClock),
            ],
            scalars: [
                "completed": (.bool(false), hlc(10, 0, dA)),
                "priority": (.string(TodoPriority.medium.rawValue), hlc(10, 0, dA)),
                "sort_order": (.int(0), hlc(10, 0, dA)),
                "complete_by": (.dateMillis(nil), hlc(10, 0, dA)),
                "completed_at": (.dateMillis(nil), hlc(10, 0, dA)),
            ],
            deletedAt: nil,
            deleteClock: nil,
            recordHLC: recordHLC,
            version: version
        )
    }

    func testNonConflictingFieldMerge() {
        let vA = VersionVector(map: [dA: hlc(100, 0, dA)])
        let vB = VersionVector(map: [dB: hlc(100, 0, dB)])
        let local = snapTodo(
            title: "A",
            description: "shared",
            titleClock: hlc(100, 0, dA),
            descClock: hlc(50, 0, dA),
            version: vA,
            recordHLC: hlc(100, 0, dA)
        )
        var remoteScalars = local.scalars
        remoteScalars["priority"] = (.string(TodoPriority.high.rawValue), hlc(100, 0, dB))
        let remote = MergeSnapshot(
            entity: .todo,
            recordId: local.recordId,
            textFields: [
                "title": ("B", hlc(100, 0, dB)),
                "description": ("shared", hlc(50, 0, dB)),
            ],
            scalars: remoteScalars,
            deletedAt: nil,
            deleteClock: nil,
            recordHLC: hlc(100, 0, dB),
            version: vB
        )
        let merged = RecordMerge.mergeRecord(local: local, remote: remote)
        XCTAssertEqual(merged.textFields["title"]?.value, "B")
        XCTAssertEqual(merged.scalars["priority"]?.value, .string(TodoPriority.high.rawValue))
    }

    func testEqualValuesNoConcat() {
        let vv = VersionVector(map: [dA: hlc(5, 0, dA)])
        let a = snapTodo(
            title: "Same",
            description: "D",
            titleClock: hlc(5, 0, dA),
            descClock: hlc(5, 0, dA),
            version: vv,
            recordHLC: hlc(5, 0, dA)
        )
        let b = snapTodo(
            title: "Same",
            description: "D",
            titleClock: hlc(6, 0, dB),
            descClock: hlc(6, 0, dB),
            version: VersionVector(map: [dB: hlc(6, 0, dB)]),
            recordHLC: hlc(6, 0, dB)
        )
        let m = RecordMerge.mergeRecord(local: a, remote: b)
        XCTAssertEqual(m.textFields["title"]?.value, "Same")
        XCTAssertFalse(m.textFields["title"]!.value.contains("merged from"))
    }

    func testConcurrentTitleConcatDeterministic() {
        let va = VersionVector(map: [dA: hlc(10, 0, dA)])
        let vb = VersionVector(map: [dB: hlc(20, 0, dB)])
        let left = snapTodo(
            title: "Left",
            description: "",
            titleClock: hlc(10, 0, dA),
            descClock: hlc(10, 0, dA),
            version: va,
            recordHLC: hlc(10, 0, dA)
        )
        let right = snapTodo(
            title: "Right",
            description: "",
            titleClock: hlc(20, 0, dB),
            descClock: hlc(20, 0, dB),
            version: vb,
            recordHLC: hlc(20, 0, dB)
        )
        let m1 = RecordMerge.mergeRecord(local: left, remote: right)
        let m2 = RecordMerge.mergeRecord(local: right, remote: left)
        XCTAssertEqual(m1.textFields["title"]?.value, m2.textFields["title"]?.value)
        XCTAssertTrue(m1.textFields["title"]!.value.contains(RecordMerge.mergedSeparator(deviceId: dB)))
    }

    func testAncestorFastForwardNoConcat() {
        let ancestorVV = VersionVector(map: [dA: hlc(1, 0, dA)])
        let childVV = VersionVector.merged(ancestorVV, VersionVector(map: [dB: hlc(2, 0, dB)]))
        let ancestor = snapTodo(
            title: "Old",
            description: "",
            titleClock: hlc(1, 0, dA),
            descClock: hlc(1, 0, dA),
            version: ancestorVV,
            recordHLC: hlc(1, 0, dA)
        )
        let child = snapTodo(
            title: "New",
            description: "",
            titleClock: hlc(2, 0, dB),
            descClock: hlc(2, 0, dB),
            version: childVV,
            recordHLC: hlc(2, 0, dB)
        )
        XCTAssertTrue(VersionVector.descends(from: ancestor.version, to: child.version))
        let m = RecordMerge.mergeRecord(local: ancestor, remote: child)
        XCTAssertEqual(m.textFields["title"]?.value, "New")
        XCTAssertFalse(m.textFields["title"]!.value.contains("merged from"))
    }

    func testEditBeatsDelete() {
        let vDel = VersionVector(map: [dA: hlc(50, 0, dA)])
        let tomb = MergeSnapshot(
            entity: .todo,
            recordId: "x",
            textFields: [:],
            scalars: [:],
            deletedAt: Date(),
            deleteClock: hlc(50, 0, dA),
            recordHLC: hlc(50, 0, dA),
            version: vDel
        )
        let live = snapTodo(
            title: "Back",
            description: "",
            titleClock: hlc(60, 0, dB),
            descClock: hlc(60, 0, dB),
            version: VersionVector(map: [dB: hlc(60, 0, dB)]),
            recordHLC: hlc(60, 0, dB)
        )
        let m = RecordMerge.mergeRecord(local: tomb, remote: live)
        XCTAssertNil(m.deletedAt)
    }

    func testMergeIdempotent() {
        let va = VersionVector(map: [dA: hlc(10, 0, dA)])
        let vb = VersionVector(map: [dB: hlc(20, 0, dB)])
        let l = snapTodo(
            title: "L",
            description: "",
            titleClock: hlc(10, 0, dA),
            descClock: hlc(10, 0, dA),
            version: va,
            recordHLC: hlc(10, 0, dA)
        )
        let r = snapTodo(
            title: "R",
            description: "",
            titleClock: hlc(20, 0, dB),
            descClock: hlc(20, 0, dB),
            version: vb,
            recordHLC: hlc(20, 0, dB)
        )
        let m = RecordMerge.mergeRecord(local: l, remote: r)
        let mL = RecordMerge.mergeRecord(local: m, remote: l)
        let mR = RecordMerge.mergeRecord(local: m, remote: r)
        XCTAssertEqual(mL.textFields["title"]?.value, m.textFields["title"]?.value)
        XCTAssertEqual(mR.textFields["title"]?.value, m.textFields["title"]?.value)
    }

    func testCommutativeTitle() {
        let va = VersionVector(map: [dA: hlc(10, 0, dA)])
        let vb = VersionVector(map: [dB: hlc(20, 0, dB)])
        let l = snapTodo(
            title: "L",
            description: "",
            titleClock: hlc(10, 0, dA),
            descClock: hlc(10, 0, dA),
            version: va,
            recordHLC: hlc(10, 0, dA)
        )
        let r = snapTodo(
            title: "R",
            description: "",
            titleClock: hlc(20, 0, dB),
            descClock: hlc(20, 0, dB),
            version: vb,
            recordHLC: hlc(20, 0, dB)
        )
        let ab = RecordMerge.mergeRecord(local: l, remote: r)
        let ba = RecordMerge.mergeRecord(local: r, remote: l)
        XCTAssertEqual(ab.textFields["title"]?.value, ba.textFields["title"]?.value)
    }

    func testMergedWithParentNoFurtherConcat() {
        let va = VersionVector(map: [dA: hlc(10, 0, dA)])
        let vb = VersionVector(map: [dB: hlc(20, 0, dB)])
        let l = snapTodo(
            title: "L",
            description: "",
            titleClock: hlc(10, 0, dA),
            descClock: hlc(10, 0, dA),
            version: va,
            recordHLC: hlc(10, 0, dA)
        )
        let r = snapTodo(
            title: "R",
            description: "",
            titleClock: hlc(20, 0, dB),
            descClock: hlc(20, 0, dB),
            version: vb,
            recordHLC: hlc(20, 0, dB)
        )
        let m = RecordMerge.mergeRecord(local: l, remote: r)
        let withL = RecordMerge.mergeRecord(local: m, remote: l)
        let withR = RecordMerge.mergeRecord(local: m, remote: r)
        XCTAssertEqual(withL.textFields["title"]?.value, m.textFields["title"]?.value)
        XCTAssertEqual(withR.textFields["title"]?.value, m.textFields["title"]?.value)
    }

    func testThreeDeviceConvergence() {
        let v1 = VersionVector(map: [dA: hlc(1, 0, dA)])
        let v2 = VersionVector(map: [dB: hlc(2, 0, dB)])
        let v3 = VersionVector(map: [dC: hlc(3, 0, dC)])
        let a = snapTodo(
            title: "A",
            description: "",
            titleClock: hlc(1, 0, dA),
            descClock: hlc(1, 0, dA),
            version: v1,
            recordHLC: hlc(1, 0, dA)
        )
        let b = snapTodo(
            title: "B",
            description: "",
            titleClock: hlc(2, 0, dB),
            descClock: hlc(2, 0, dB),
            version: v2,
            recordHLC: hlc(2, 0, dB)
        )
        let c = snapTodo(
            title: "C",
            description: "",
            titleClock: hlc(3, 0, dC),
            descClock: hlc(3, 0, dC),
            version: v3,
            recordHLC: hlc(3, 0, dC)
        )
        let mAB = RecordMerge.mergeRecord(local: a, remote: b)
        let mABC = RecordMerge.mergeRecord(local: mAB, remote: c)
        let mAC = RecordMerge.mergeRecord(local: a, remote: c)
        let mACB = RecordMerge.mergeRecord(local: mAC, remote: b)
        XCTAssertEqual(mABC.textFields["title"]?.value, mACB.textFields["title"]?.value)
    }
}
