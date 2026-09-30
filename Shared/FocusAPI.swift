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
}
