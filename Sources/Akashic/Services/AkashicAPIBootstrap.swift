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

    /// Serve `/health` (200) and every `/api/*` as 423 while the vault is locked / on cold start.
    static func startLockedOnly(apiService: AkashicAPIService) {
        server.startLockedOnly(apiService: apiService)
    }

    static func stop() {
        server.stop()
    }
}
