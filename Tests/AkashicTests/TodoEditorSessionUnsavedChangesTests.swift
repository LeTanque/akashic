import XCTest
@testable import Akashic

@MainActor
final class TodoEditorSessionUnsavedChangesTests: XCTestCase {
    func testResolveUnsavedChangesSkipsPresenterWhenClean() throws {
        let store = try TodoStore.isolatedForTesting()
        var presented = false
        let session = TodoEditorSession { _ in
            presented = true
            return .cancel
        }
        XCTAssertTrue(session.resolveUnsavedChanges(store: store))
        XCTAssertFalse(presented)
    }

    func testResolveUnsavedChangesSavePersistsAndAllowsNavigation() throws {
        let store = try TodoStore.isolatedForTesting()
        let session = TodoEditorSession { _ in .save }
        session.mutateForm { $0.draft.title = "Draft title" }
        XCTAssertTrue(session.resolveUnsavedChanges(store: store))
        XCTAssertEqual(store.todos.first?.title, "Draft title")
        XCTAssertFalse(session.form.isDirty)
    }

    func testResolveUnsavedChangesDiscardClearsEdits() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Baseline", description: "")
        let session = TodoEditorSession { _ in .discard }
        session.mutateForm { $0.load(item) }
        session.mutateForm { $0.draft.title = "Temporary" }
        XCTAssertTrue(session.resolveUnsavedChanges(store: store))
        XCTAssertEqual(session.form.draft.title, "Baseline")
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.title, "Baseline")
    }

    func testResolveUnsavedChangesCancelBlocksNavigation() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Keep selection", description: "")
        store.selectedTodoID = item.id
        let session = TodoEditorSession { _ in .cancel }
        session.mutateForm { $0.load(item) }
        session.mutateForm { $0.draft.title = "Blocked" }
        XCTAssertFalse(session.resolveUnsavedChanges(store: store))
        XCTAssertEqual(session.form.draft.title, "Blocked")
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.title, "Keep selection")
    }

    func testPresenterSeamReceivesTodoDisplayName() throws {
        let store = try TodoStore.isolatedForTesting()
        var captured = ""
        let session = TodoEditorSession { name in
            captured = name
            return .cancel
        }
        session.mutateForm { $0.draft.title = "  My todo  " }
        _ = session.resolveUnsavedChanges(store: store)
        XCTAssertEqual(captured, "My todo")
    }

    func testPresenterSeamUsesNewTodoLabelForBlankNewDraft() throws {
        let store = try TodoStore.isolatedForTesting()
        var captured = ""
        let session = TodoEditorSession { name in
            captured = name
            return .cancel
        }
        session.mutateForm { $0.draft.description = "Only body" }
        _ = session.resolveUnsavedChanges(store: store)
        XCTAssertEqual(captured, "New todo")
    }

    func testSelectTodoBlockedWhenPresenterReturnsCancel() throws {
        let store = try TodoStore.isolatedForTesting()
        let first = store.createTodo(title: "First", description: "")
        let second = store.createTodo(title: "Second", description: "")
        store.selectedTodoID = first.id
        let session = TodoEditorSession { _ in .cancel }
        session.mutateForm { $0.load(first) }
        session.mutateForm { $0.draft.title = "Dirty first" }
        XCTAssertFalse(session.selectTodo(second, store: store))
        XCTAssertEqual(store.selectedTodoID, first.id)
        XCTAssertEqual(session.form.draft.title, "Dirty first")
    }

    func testConfirmQuitRoutesThroughPresenter() throws {
        let store = try TodoStore.isolatedForTesting()
        let session = TodoEditorSession { _ in .cancel }
        session.mutateForm { $0.draft.title = "Quit blocked" }
        XCTAssertFalse(session.confirmQuit(store: store))
    }

    func testThemedUnsavedChangesPresenterUsesSettingsChrome() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Services/UnsavedChangesAlertPresenter.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("AkashicSettingsChamferedEffectView"))
        XCTAssertTrue(source.contains("UNSAVED CHANGES"))
        XCTAssertTrue(source.contains("NSApp.runModal(for: panel)"))
        XCTAssertTrue(source.contains("CyberpunkTheme.neonOrange"))
        XCTAssertTrue(source.contains("save.keyEquivalent = \"\\r\""))
        XCTAssertTrue(source.contains("cancel.keyEquivalent = \"\\u{1b}\""))
        XCTAssertFalse(source.contains("NSAlert"))
    }
}
