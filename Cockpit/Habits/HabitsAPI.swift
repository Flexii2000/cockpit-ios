import Foundation

/// Die Endpunkte des Habits-Dienstes. Siehe docs/BACKENDS.md.
///
/// Zugang ueber den Privat-Cookie `fh_private`, den `Access.applyCookies()`
/// fuer `.fherrmann.com` setzt - derselbe wie beim Kalorienzaehler. Nichts
/// Neues einzutragen.
struct HabitsAPI: Sendable {

    private let client = APIClient(backend: .habits, timeout: 30)

    func list() async throws -> [HabitStatus] {
        try await client.get("/api/habits")
    }

    func create(_ draft: HabitDraft) async throws -> HabitStatus {
        try await client.send("POST", "/api/habits", body: draft)
    }

    func delete(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/habits/\(id)")
    }

    /// Haken (Build) oder Rueckfall (Quit) fuer heute.
    func mark(id: String) async throws -> HabitStatus {
        try await client.send("POST", "/api/habits/\(id)/marks", body: MarkRequest(date: nil))
    }

    func unmark(id: String, date: CalendarDate) async throws -> HabitStatus {
        try await client.delete("/api/habits/\(id)/marks/\(date.iso)")
    }

    private struct MarkRequest: Encodable {
        let date: String?
    }
}
