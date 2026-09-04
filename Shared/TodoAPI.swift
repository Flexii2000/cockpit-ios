import Foundation

/// Die Endpunkte des To-Do-Dienstes. Zugang ueber den Privat-Cookie wie bei
/// Habits - nichts Neues einzutragen.
struct TodoAPI: Sendable {

    private let client: APIClient

    init(cookie: String? = nil, timeout: TimeInterval = 30) {
        client = APIClient(backend: .todo, cookie: cookie, timeout: timeout)
    }

    func board(includeHidden: Bool = false) async throws -> TodoBoard {
        try await client.get("/api/board", query: includeHidden
                             ? [URLQueryItem(name: "all", value: "true")] : [])
    }

    func createArea(name: String) async throws -> TodoBoard {
        try await client.send("POST", "/api/areas", body: AreaDraft(name: name))
    }

    func renameArea(id: String, name: String) async throws -> TodoBoard {
        try await client.send("PUT", "/api/areas/\(id)", body: AreaDraft(name: name))
    }

    func deleteArea(id: String) async throws -> TodoBoard {
        try await client.delete("/api/areas/\(id)")
    }

    func create(_ draft: TodoDraft) async throws -> TodoBoard {
        try await client.send("POST", "/api/todos", body: draft)
    }

    /// Abhaken darf ohne Netz warten: der Dienst merkt sich den ersten
    /// Zeitpunkt, ein Nachsenden ist idempotent.
    func done(id: String) async throws -> TodoBoard {
        try await client.send("POST", "/api/todos/\(id)/done", body: Empty(), queueWhenOffline: true)
    }

    func reopen(id: String) async throws -> TodoBoard {
        try await client.delete("/api/todos/\(id)/done", queueWhenOffline: true)
    }

    func delete(id: String) async throws -> TodoBoard {
        try await client.delete("/api/todos/\(id)")
    }

    private struct Empty: Encodable {}
}
