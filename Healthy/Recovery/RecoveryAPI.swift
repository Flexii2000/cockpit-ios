import Foundation

/// Naechte und Recovery beim Weight Tracker. Siehe docs/BACKENDS.md und den
/// Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §2 und §3.
struct RecoveryAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Hoechstens so viele Naechte je Anfrage. Der Dienst naehme 400, aber
    /// nginx laesst dort nur 1 MB durch - und eine 413 ist eine HTML-Seite,
    /// kein JSON.
    static let nightsPerRequest = 200

    /// Schickt Naechte, in Bloecken zu hoechstens 200.
    ///
    /// Ohne Postausgang: eine Nacht wird beim Dienst als Ganzes ersetzt, und
    /// der Abgleich bildet sie beim naechsten Mal ohnehin neu.
    func sendNights(_ nights: [Night]) async throws {
        var start = nights.startIndex
        while start < nights.endIndex {
            let end = min(start + Self.nightsPerRequest, nights.endIndex)
            let _: [Night] = try await client.send("POST", "/api/nights",
                                                   body: NightsUpload(nights: Array(nights[start..<end])))
            start = end
        }
    }
}

extension RecoveryAPI {

    /// Hoechstens so viele Tage nimmt `GET /api/recovery` auf einmal.
    static let maxDays = 400

    /// Heute - `noNight`, solange die Nacht noch nicht angekommen ist.
    func today() async throws -> RecoveryDay {
        try await client.get("/api/recovery/today")
    }

    /// Tage mit einer Nacht im Zeitraum; Tage ohne fehlen.
    func days(from: CalendarDate, to: CalendarDate) async throws -> [RecoveryDay] {
        try await client.get("/api/recovery", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    func settings() async throws -> RecoverySettings {
        try await client.get("/api/recovery/settings")
    }

    /// Ohne Postausgang: eine Einstellung will man sofort bestaetigt sehen -
    /// und sie aendert auch alte Scores, die die Seite gleich neu zeigt.
    func updateSettings(sleepNeedMinutes: Int) async throws -> RecoverySettings {
        try await client.send("PUT", "/api/recovery/settings",
                              body: RecoverySettings(sleepNeedMinutes: sleepNeedMinutes))
    }
}
