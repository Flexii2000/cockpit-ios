import Foundation

/// Die Padel-Autobuchung (`fherrmann.com/padel`, Dienst `../padel`). Nur Endpunkte - jede
/// Aenderung antwortet mit der neuen Uebersicht bzw. den Buchungen, gezeigt wird die Antwort.
/// Nichts davon geht in den Postausgang: ob ausgesetzt, gebucht oder storniert ist, muss man
/// jetzt wissen.
struct PadelAPI: Sendable {

    private let client = APIClient(backend: .padel)

    func overview() async throws -> PadelOverview {
        try await client.get("/api/overview")
    }

    /// Live aus Playtomic - dauert einen Moment und kann fuer sich scheitern.
    func bookings() async throws -> [PadelBooking] {
        try await client.get("/api/bookings")
    }

    // MARK: - Termine

    func skip(_ id: String, day: Bool) async throws -> PadelOverview {
        try await client.send("POST", "/api/occurrences/\(id)/skip", query: Self.day(day))
    }

    func unskip(_ id: String, day: Bool) async throws -> PadelOverview {
        try await client.send("POST", "/api/occurrences/\(id)/unskip", query: Self.day(day))
    }

    func retry(_ id: String) async throws -> PadelOverview {
        try await client.send("POST", "/api/occurrences/\(id)/retry")
    }

    func remove(_ id: String, day: Bool) async throws -> PadelOverview {
        try await client.send("DELETE", "/api/occurrences/\(id)", query: Self.day(day))
    }

    func move(_ id: String, to slot: PadelSlotRequest) async throws -> PadelOverview {
        try await client.send("PUT", "/api/occurrences/\(id)", query: [], body: slot)
    }

    func addOneOff(_ slot: PadelSlotRequest) async throws -> PadelOverview {
        try await client.send("POST", "/api/occurrences", query: [], body: slot)
    }

    // MARK: - Serien und Plaetze

    func createSeries(_ series: PadelSeriesRequest) async throws -> PadelOverview {
        try await client.send("POST", "/api/series", query: [], body: series)
    }

    func updateSeries(_ id: String, _ series: PadelSeriesRequest) async throws -> PadelOverview {
        try await client.send("PUT", "/api/series/\(id)", query: [], body: series)
    }

    func deleteSeries(_ id: String) async throws -> PadelOverview {
        try await client.send("DELETE", "/api/series/\(id)")
    }

    func courtOrder(_ ids: [String]) async throws -> PadelOverview {
        try await client.send("PUT", "/api/settings", query: [], body: PadelSettingsRequest(courtOrder: ids))
    }

    // MARK: - Buchungen

    func cancel(_ matchId: String) async throws -> [PadelBooking] {
        try await client.send("POST", "/api/bookings/\(matchId)/cancel")
    }

    func publish(_ matchId: String) async throws -> [PadelBooking] {
        try await client.send("POST", "/api/bookings/\(matchId)/publish")
    }

    func merge(_ matchId: String) async throws -> [PadelBooking] {
        try await client.send("POST", "/api/bookings/\(matchId)/merge")
    }

    private static func day(_ wholeDay: Bool) -> [URLQueryItem] {
        wholeDay ? [URLQueryItem(name: "day", value: "true")] : []
    }
}
