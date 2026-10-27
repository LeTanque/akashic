import XCTest
@testable import Akashic

@MainActor
final class NoteFormModelTests: XCTestCase {
    func testBlankDraftNotSavedUntilExplicitSave() throws {
        let store = try NoteStore.isolatedForTesting()
        var form = NoteFormModel.blank()
        form.draft.title = "Draft title"
        form.draft.body = "In progress"
        XCTAssertTrue(form.isDirty)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNotNil(form.save(into: store))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testUnsavedChangesGuardWhenDirty() {
        var form = NoteFormModel.blank()
        form.draft.title = "x"
        XCTAssertEqual(NoteFormModel.unsavedChangesGuard(isDirty: form.isDirty), .needsConfirmation)
    }

    func testParseTagsFromInput() {
        var form = NoteFormModel.blank()
        form.tagInput = "work, ideas\nextra"
        form.commitTagsFromInput()
        XCTAssertEqual(form.draft.tags.map(\.name), ["work", "ideas", "extra"])
        XCTAssertTrue(form.tagInput.isEmpty)
    }
}
