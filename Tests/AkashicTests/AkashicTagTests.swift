import XCTest
@testable import Akashic

final class AkashicTagTests: XCTestCase {
    func testPaletteValidationUnknownFallsBackToDefault() {
        XCTAssertEqual(AkashicTagColor.validated(nil), .cyan)
        XCTAssertEqual(AkashicTagColor.validated("not-a-color"), .cyan)
        XCTAssertNil(AkashicTagColor.parseStrict("not-a-color"))
        XCTAssertEqual(AkashicTagColor.validated("ORANGE"), .orange)
        XCTAssertEqual(AkashicTagColor.validated("electric-blue"), .electricBlue)
    }

    func testParseInputClampsNewNamesToMaxLength() {
        let long = String(repeating: "a", count: 30)
        XCTAssertEqual(
            NoteTagNormalization.parseInput(long + ", b"),
            [String(repeating: "a", count: NoteTagNormalization.maxNameLength), "b"]
        )
    }

    func testNormalizeTagsKeepsExistingLongNamesIntact() {
        let legacy = "this is one long tag name" // 25 chars, saved before the limit
        let tags = NoteTagNormalization.normalizeTags([AkashicTag(name: legacy, color: .orange)])
        XCTAssertEqual(tags.map(\.name), [legacy])
        XCTAssertEqual(tags.first?.nameKey, legacy)
    }

    func testCapTagInputCapsEachSegmentAndKeepsReturn() {
        let max = NoteTagNormalization.maxNameLength
        let full = String(repeating: "x", count: max)
        XCTAssertEqual(NoteTagNormalization.capTagInput(full + "y"), full)
        XCTAssertEqual(NoteTagNormalization.capTagInput(full + "\n"), full + "\n")
        XCTAssertEqual(NoteTagNormalization.capTagInput("ab," + full + "zz"), "ab," + full)
    }

    func testAPITagNameLengthValidationRejectsLongNames() {
        let long = String(repeating: "z", count: 25)
        XCTAssertNotNil(NoteTagNormalization.apiTagNameLengthError(in: [long]))
        XCTAssertNil(NoteTagNormalization.apiTagNameLengthError(in: ["short"]))
    }

    func testNormalizeTagsTrimsDedupesPreservesCase() {
        let tags = NoteTagNormalization.normalizeTags([
            AkashicTag(name: " Work ", color: .orange),
            AkashicTag(name: "work", color: .red),
            AkashicTag(name: "", color: .green),
            AkashicTag(name: "Ideas", color: .purple),
        ])
        XCTAssertEqual(tags.map(\.name), ["Work", "Ideas"])
        XCTAssertEqual(tags.first?.color, .orange)
    }

    @MainActor
    func testNoteFormNotDirtyWhenOnlyTagColorDiffers() throws {
        let store = try NoteStore.isolatedForTesting()
        var form = NoteFormModel.blank()
        form.draft.title = "Title"
        form.draft.tags = [AkashicTag(name: "work", color: .cyan)]
        _ = form.save(into: store)
        let saved = try XCTUnwrap(store.notes.first)
        form.load(saved)
        XCTAssertEqual(form.draft.tags.first?.color, .cyan)
        form.draft.tags = [AkashicTag(name: "work", color: .orange)]
        XCTAssertFalse(form.isDirty)
    }
}
