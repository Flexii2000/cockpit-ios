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

    // MARK: - Der Wald

    /// Die Sessions eines Zeitraums, neueste zuerst.
    func focusSessions(from: CalendarDate, to: CalendarDate) async throws -> [FocusSession] {
        try await client.get("/api/focus/sessions", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    /// Meldet eine durchgestandene Session. Ohne Netz in den Postausgang:
    /// der Baum steht dann, sobald wieder Netz da ist - und nur einmal, weil
    /// die Id mitgeht.
    func plant(_ draft: FocusSessionDraft) async throws -> FocusSession {
        try await client.send("POST", "/api/focus/sessions", body: draft, queueWhenOffline: true)
    }

    /// Name und Zielwerte aendern - die Art nicht, das laesst der Dienst nicht zu.
    func update(id: String, _ draft: HabitDraft) async throws -> HabitStatus {
        try await client.send("PUT", "/api/habits/\(id)", body: draft)
    }

    func delete(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/habits/\(id)")
    }

    /// Haken (Build) oder Rueckfall (Quit) fuer heute.
    ///
    /// Mit ausdruecklichem Datum, obwohl der Dienst „heute" auch ohne
    /// versteht: liegt der Haken ohne Netz im Postausgang und geht erst morgen
    /// raus, waere „heute" dann der falsche Tag.
    func mark(id: String, date: CalendarDate = .today()) async throws -> HabitStatus {
        try await client.send("POST", "/api/habits/\(id)/marks",
                              body: MarkRequest(date: date.iso),
                              queueWhenOffline: true)
    }

    func unmark(id: String, date: CalendarDate) async throws -> HabitStatus {
        try await client.delete("/api/habits/\(id)/marks/\(date.iso)", queueWhenOffline: true)
    }

    private struct MarkRequest: Encodable {
        let date: String?
    }
}
