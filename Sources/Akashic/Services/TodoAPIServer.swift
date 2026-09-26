import Foundation
import FlyingFox
import FlyingSocks

/// In-process localhost HTTP API. Same GRDB/SQLite store as the UI — no separate database.
final class TodoAPIServer: @unchecked Sendable {
    static let port: UInt16 = 4311

    private var runTask: Task<Void, Never>?

    func start(store: TodoStore) {
        guard runTask == nil else { return }
        let port = Self.port
        runTask = Task.detached(priority: .utility) {
            // IPv4 localhost so http://127.0.0.1:4311 and http://localhost:4311 both work.
            guard let address = try? sockaddr_in.inet(ip4: "127.0.0.1", port: port) else {
                NSLog("Akashic API server: failed to bind 127.0.0.1:%d", port)
                return
            }
            let server = HTTPServer(address: address, logger: .disabled)
            await Self.installRoutes(on: server, store: store)
            do {
                try await server.run()
            } catch {
                NSLog("Akashic API server stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    private static func installRoutes(on server: HTTPServer, store: TodoStore) async {
        await server.appendRoute("GET /health") { _ in
            json(["status": "ok", "database": "connected", "app": "akashic"])
        }

        await server.appendRoute("GET /api/todos") { request in
            let status = request.query["status"] ?? "all"
            let items = await MainActor.run { store.todos(status: status).map(TodoAPIDTO.init) }
            return json(["todos": items])
        }

        await server.appendRoute("POST /api/todos") { request in
            let bodyData = try await request.bodyData
            let body = try? JSONDecoder().decode(CreateTodoBody.self, from: bodyData)
            guard let body else {
                return json(["error": "invalid JSON body"], status: .badRequest)
            }
            let trimmed = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return json(["error": "title required (1–200 chars)"], status: .badRequest)
            }
            let title = String(trimmed.prefix(200))
            let priority = TodoPriority(rawValue: body.priority ?? "medium") ?? .medium
            let item = await MainActor.run {
                store.createTodo(
                    title: title,
                    description: body.description ?? "",
                    priority: priority
                )
            }
            return json(["todo": TodoAPIDTO(item)], status: .created)
        }

        await server.appendRoute("PATCH /api/todos/:id") { request in
            guard let idString = request.routeParameters["id"],
                  let id = UUID(uuidString: idString) else {
                return json(["error": "invalid id"], status: .badRequest)
            }
            let bodyData = try await request.bodyData
            let body = try? JSONDecoder().decode(PatchTodoBody.self, from: bodyData)
            guard let body else {
                return json(["error": "invalid JSON body"], status: .badRequest)
            }
            let priority = body.priority.flatMap(TodoPriority.init(rawValue:))
            let completeBy = body.complete_by.flatMap(parseDate)
            let updated = await MainActor.run {
                store.applyPatch(
                    id: id,
                    title: body.title.map { String($0.prefix(200)) },
                    description: body.description,
                    completed: body.completed,
                    priority: priority,
                    completeBy: completeBy
                )
            }
            guard let updated else {
                return json(["error": "not found"], status: .notFound)
            }
            return json(["todo": TodoAPIDTO(updated)])
        }

        await server.appendRoute("DELETE /api/todos/:id") { request in
            guard let idString = request.routeParameters["id"],
                  let id = UUID(uuidString: idString) else {
                return json(["error": "invalid id"], status: .badRequest)
            }
            let ok = await MainActor.run { store.delete(id: id) }
            if ok {
                return HTTPResponse(statusCode: .noContent)
            }
            return json(["error": "not found"], status: .notFound)
        }

        await server.appendRoute("PUT /v1/agent-metrics") { request in
            let bodyData = try await request.bodyData
            switch AgentMetricsPayload.parse(bodyData) {
            case .success(let payload):
                await AgentMetricsStore.shared.replace(payload)
                return json(payload)
            case .failure(let error):
                return json(["error": error.message], status: .badRequest)
            }
        }

        await server.appendRoute("GET /v1/agent-metrics") { _ in
            if let payload = await AgentMetricsStore.shared.lastPayload {
                return json(payload)
            }
            return json(["error": "no agent metrics yet"], status: .notFound)
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone.current
        local.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        if let d = local.date(from: raw) { return d }
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return local.date(from: raw)
    }
}

// MARK: - DTOs

private struct TodoAPIDTO: Encodable {
    let id: String
    let title: String
    let description: String
    let completed: Bool
    let priority: String
    let complete_by: String?
    let created_at: String
    let updated_at: String
    let completed_at: String?

    init(_ item: TodoItem) {
        id = item.id.uuidString
        title = item.title
        description = item.description
        completed = item.completed
        priority = item.priority.rawValue
        complete_by = item.completeBy.map(Self.encodeDate)
        created_at = Self.encodeDate(item.createdOn)
        updated_at = Self.encodeDate(item.updatedAt)
        completed_at = item.completedAt.map(Self.encodeDate)
    }

    private static func encodeDate(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: date)
    }
}

private struct CreateTodoBody: Decodable {
    let title: String
    let description: String?
    let priority: String?
}

private struct PatchTodoBody: Decodable {
    let title: String?
    let description: String?
    let completed: Bool?
    let priority: String?
    let complete_by: String?
}

private func json<T: Encodable>(_ value: T, status: HTTPStatusCode = .ok) -> HTTPResponse {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(value)) ?? Data(#"{}"#.utf8)
    return HTTPResponse(
        statusCode: status,
        headers: [.contentType: "application/json"],
        body: data
    )
}
