import Foundation

@MainActor
enum AkashicAPIBootstrap {
    private static let server = TodoAPIServer()

    static func startIfNeeded(
        todoStore: TodoStore,
        noteStore: NoteStore,
        apiService: AkashicAPIService
    ) {
        server.start(store: todoStore, noteStore: noteStore, apiService: apiService)
    }

    static func stop() {
        server.stop()
    }
}
