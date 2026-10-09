import Foundation

/// Die Energiebilanz beim Weight Tracker. Siehe docs/BACKENDS.md und den
/// Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §1.
struct EnergyAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// So viele Tage nimmt der Dienst auf einmal - genug fuer „Alles".
    static let maxDays = 4000

    /// Tage mit Werten der Uhr oder des Kalorienzaehlers; andere fehlen, nie
    /// einer nach heute.
    func days(from: CalendarDate, to: CalendarDate) async throws -> [EnergyDay] {
        try await client.get("/api/energy", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    func summary() async throws -> EnergySummary {
        try await client.get("/api/energy/summary")
    }

    /// Schickt ein Fenster von Tagen.
    ///
    /// Bewusst ohne Postausgang: der Abgleich liest beim naechsten Mal
    /// dasselbe Fenster wieder - was jetzt nicht ankommt, kommt dann.
    ///
    /// - Returns: der **gespeicherte** Stand dieser Tage. Heute und gestern
    ///   kann er hoeher sein als das Geschickte (Maximum je Feld).
    @discardableResult
    func send(_ days: [EnergyDayUpload]) async throws -> [EnergyDayUpload] {
        try await client.send("POST", "/api/energy", body: EnergyUpload(days: days, replace: nil))
    }

    /// Der Anfang eines Zeitraums, gekuerzt auf das, was der Dienst nimmt.
    static func clampedStart(from: CalendarDate, to: CalendarDate) -> CalendarDate {
        let earliest = to.adding(days: -(maxDays - 1))
        return from < earliest ? earliest : from
    }
}
