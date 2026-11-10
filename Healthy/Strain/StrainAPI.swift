import Foundation

/// Der Strain beim Weight Tracker. Siehe docs/BACKENDS.md und den Vertrag
/// `weight-app/docs/HEALTHY-CONTRACT.md` §7.
struct StrainAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Hoechstens so viele Tage je Anfrage. Der Dienst naehme 400, aber nginx
    /// laesst dort nur 1 MB durch (Vertrag §7.1).
    static let daysPerRequest = 60

    /// Hoechstens so viele Tage nimmt `GET /api/strain` auf einmal.
    static let maxDays = 400

    /// Schickt Puls-Histogramme, in Bloecken zu hoechstens 60 Tagen.
    ///
    /// Ohne Postausgang: der Abgleich liest beim naechsten Mal dasselbe
    /// Fenster wieder - was jetzt nicht ankommt, kommt dann.
    func send(_ days: [HeartDayUpload]) async throws {
        var start = days.startIndex
        while start < days.endIndex {
            let end = min(start + Self.daysPerRequest, days.endIndex)
            let _: [StrainStored] = try await client.send(
                "POST", "/api/strain", body: HeartUpload(days: Array(days[start..<end]), replace: nil))
            start = end
        }
    }

    /// Heute - `noData`, solange noch kein Histogramm angekommen ist; das
    /// Ziel steht trotzdem da.
    func today() async throws -> StrainDay {
        try await client.get("/api/strain/today")
    }

    /// Jeder Kalendertag ab dem ersten gespeicherten, hoechstens bis heute;
    /// ohne einen gespeicherten Tag leer.
    func days(from: CalendarDate, to: CalendarDate) async throws -> [StrainDay] {
        try await client.get("/api/strain", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    func settings() async throws -> StrainSettings {
        try await client.get("/api/strain/settings")
    }

    /// Legt den Maximalpuls fest (120–230) oder gibt ihn mit `nil` wieder frei.
    /// Aendert auch die Vergangenheit - der Dienst rechnet bei jeder Anfrage neu.
    func updateSettings(hrMax: Double?) async throws -> StrainSettings {
        try await client.send("PUT", "/api/strain/settings", body: StrainSettingsRequest(hrMax: hrMax))
    }
}
