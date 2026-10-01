import Foundation

/// Die Fokus-Sessions des Waldes beim Habits-Dienst
/// (`/habits/api/focus/sessions`). Siehe docs/BACKENDS.md.
///
/// Die Habits selbst sind nach coHabit umgezogen (`/habits/api/habits/**`
/// antwortet mit 410); die Sessions bleiben, wo sie waren - aus ihnen rechnet
/// das Co-Habit mit der Quelle „Fokus-Zeit".
///
/// Zugang ueber den Privat-Cookie `fh_private`, den `Access.applyCookies()`
/// fuer `.fherrmann.com` setzt.
struct FocusSessionsAPI: Sendable {

    private let client: APIClient

    init(timeout: TimeInterval = 30) {
        client = APIClient(backend: .habits, timeout: timeout)
    }

    /// Die Sessions eines Zeitraums, neueste zuerst.
    func sessions(from: CalendarDate, to: CalendarDate) async throws -> [FocusSession] {
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

    // MARK: - Kategorien

    /// Die Kategorien zur Auswahl, in der Reihenfolge des Anlegens - ohne Netz
    /// der letzte Stand.
    func categories() async throws -> [FocusCategory] {
        try await client.get("/api/focus/categories")
    }

    /// Anlegen, umbenennen und loeschen nur mit Netz, ohne Postausgang: eine
    /// offline angelegte Kategorie, die beim Nachsenden scheitert (Name
    /// inzwischen vergeben), naehme jeden Baum mit ihr mit - der Dienst lehnt
    /// eine unbekannte Kategorie ab. Ohne Netz bleibt die Auswahl der Liste.
    func createCategory(name: String) async throws -> FocusCategory {
        try await client.send("POST", "/api/focus/categories", body: FocusCategoryDraft(name: name))
    }

    func renameCategory(id: String, name: String) async throws -> FocusCategory {
        try await client.send("PUT", "/api/focus/categories/\(id)", body: FocusCategoryDraft(name: name))
    }

    /// Nur aus der Auswahl - alte Baeume behalten den Namen.
    func deleteCategory(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/focus/categories/\(id)")
    }
}
