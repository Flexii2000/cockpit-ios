import Foundation

/// Die Energiebilanz beim Weight Tracker. Siehe docs/BACKENDS.md und den
/// Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §1.
struct EnergyAPI: Sendable {

    private let client = APIClient(backend: .weight)

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
}
