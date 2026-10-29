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

    func testNormalizeTagsClampsNamesToMaxLength() {
        let long = String(repeating: "a", count: 30)
        let tags = NoteTagNormalization.normalizeTags([
            AkashicTag(name: long, color: .cyan),
        ])
        XCTAssertEqual(tags.map(\.name), [String(repeating: "a", count: NoteTagNormalization.maxNameLength)])
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
