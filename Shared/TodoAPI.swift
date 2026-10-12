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

    // Anlegen, Abhaken, Aendern und Loeschen von Aufgaben gehen nicht hier
    // entlang, sondern durch die Warteschlange (`TodoChange`, `PendingChanges`):
    // sofort zu sehen, spaeter geschickt. Hier bleibt, was eine Antwort braucht.

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
}
