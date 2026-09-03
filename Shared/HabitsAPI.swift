import Foundation

/// Die Endpunkte des Habits-Dienstes. Siehe docs/BACKENDS.md.
///
/// Zugang ueber den Privat-Cookie `fh_private`, den `Access.applyCookies()`
/// fuer `.fherrmann.com` setzt - derselbe wie beim Kalorienzaehler. Nichts
/// Neues einzutragen.
struct HabitsAPI: Sendable {

    private let client: APIClient

    /// - Parameters:
    ///   - cookie: nur fuer die Widget-Erweiterung, die keinen gemeinsamen
    ///     Cookie-Speicher hat.
    ///   - timeout: in einer Erweiterung ist das Zeitbudget knapp.
    init(cookie: String? = nil, timeout: TimeInterval = 30) {
        client = APIClient(backend: .habits, cookie: cookie, timeout: timeout)
    }

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
    ///
    /// Mit ausdruecklichem Datum, obwohl der Dienst „heute" auch ohne
    /// versteht: liegt der Haken ohne Netz im Postausgang und geht erst morgen
    /// raus, waere „heute" dann der falsche Tag.
    func mark(id: String) async throws -> HabitStatus {
        try await client.send("POST", "/api/habits/\(id)/marks",
                              body: MarkRequest(date: CalendarDate.today().iso),
                              queueWhenOffline: true)
    }

    func unmark(id: String, date: CalendarDate) async throws -> HabitStatus {
        try await client.delete("/api/habits/\(id)/marks/\(date.iso)", queueWhenOffline: true)
    }

    private struct MarkRequest: Encodable {
        let date: String?
    }
}
