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
