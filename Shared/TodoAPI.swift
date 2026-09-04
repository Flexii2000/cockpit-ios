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

    func update(id: String, title: String, dueAt: CalendarDate?) async throws -> TodoBoard {
        try await client.send("PUT", "/api/todos/\(id)", body: TodoUpdate(title: title, dueAt: dueAt?.iso))
    }

    func addReminder(id: String, at: Date) async throws -> TodoBoard {
        try await client.send("POST", "/api/todos/\(id)/reminders", body: ReminderDraft(at: at))
    }

    func deleteReminder(id: String, reminderId: String) async throws -> TodoBoard {
        try await client.delete("/api/todos/\(id)/reminders/\(reminderId)")
    }

    /// Meldet die Push-Kennung fuer Erinnerungen an.
    func registerDevice(token: String) async throws {
        let _: APIClient.Empty = try await client.send("POST", "/api/devices", body: DeviceRegistration(token: token))
    }

    private struct DeviceRegistration: Encodable {
        let token: String
    }

    private struct Empty: Encodable {}
}
