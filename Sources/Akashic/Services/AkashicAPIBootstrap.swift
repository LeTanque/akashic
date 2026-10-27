import Foundation

@MainActor
enum AkashicAPIBootstrap {
    private static var didStart = false
    private static let server = TodoAPIServer()

    static func startIfNeeded(todoStore: TodoStore, noteStore: NoteStore) {
        guard !didStart else { return }
        didStart = true
        server.start(store: todoStore, noteStore: noteStore)
    }
}
