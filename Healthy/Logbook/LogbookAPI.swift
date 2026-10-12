import Foundation

/// Das Logbook beim Weight Tracker. Siehe docs/BACKENDS.md und den Vertrag
/// `weight-app/docs/HEALTHY-CONTRACT.md` §4.
struct LogbookAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Die Zeitraeume, fuer die der Dienst Effekte rechnet.
    static let periods = [30, 90, 180, 365]
    static let defaultPeriod = 90

    func overview() async throws -> LogbookOverview {
        try await client.get("/api/logbook")
    }

    // MARK: - Verhaltensweisen

    /// Anlegen, Aendern und Loeschen nur mit Netz: das sind keine Aenderungen,
    /// die spaeter genauso gelten - die Kennung vergibt erst der Dienst, und
    /// Loeschen nimmt alle Werte mit.
    func addBehavior(name: String, unit: String?) async throws -> Behavior {
        try await client.send("POST", "/api/logbook/behaviors", body: NewBehaviorRequest(name: name, unit: unit))
    }

    func updateBehavior(id: String, name: String? = nil, archived: Bool? = nil) async throws -> Behavior {
        try await client.send("PUT", "/api/logbook/behaviors/\(id)",
                              body: BehaviorUpdateRequest(name: name, archived: archived))
    }

    func deleteBehavior(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/logbook/behaviors/\(id)")
    }

    // MARK: - Tage

    // Werte schreibt die Warteschlange (`LogbookChange`), je Tipp einer - sofort
    // zu sehen, ohne Netz spaeter.

    func days(from: CalendarDate, to: CalendarDate) async throws -> [LogbookDay] {
        try await client.get("/api/logbook/days", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    // MARK: - Effekte

    func insights(days: Int) async throws -> LogbookInsights {
        try await client.get("/api/logbook/insights", query: [URLQueryItem(name: "days", value: String(days))])
    }
}
