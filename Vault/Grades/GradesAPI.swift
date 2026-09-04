import Foundation

/// Die Endpunkte der Notenuebersicht. Siehe docs/BACKENDS.md.
///
/// Zwei Schranken hintereinander (beide als Cookie):
///
/// 1. **Geraete-Token** - ohne ihn antwortet der Dienst mit 404, nicht mit
///    403. Wer den Pfad raet, soll nicht erfahren, dass er richtig geraten hat.
/// 2. **Anmeldung** - Benutzer und Passwort, danach eine Sitzung fuer sieben
///    Tage, die sich bei Nutzung verlaengert. Ohne sie: 401.
struct GradesAPI: Sendable {

    private let client = APIClient(backend: .grades,
                                   // Hier laeuft keine Claude-Session wie bei
                                   // der Schnellerfassung - eine Antwort, die
                                   // laenger als ein paar Sekunden braucht,
                                   // ist eine Stoerung und keine Rechnung.
                                   timeout: 30)

    func login(user: String, password: String) async throws {
        let _: LoginResponse = try await client.send(
            "POST", "/api/login", body: Login(username: user, password: password))
    }

    func overview() async throws -> GradesOverview {
        try await client.get("/api/overview")
    }

    /// Dieselbe Uebersicht, aber mit angenommenen Noten fuer offene Module.
    ///
    /// Die Annahmen gehen bei jeder Anfrage mit, statt auf dem Server zu
    /// liegen: gerechnet wird dort (die Regel aus PO-I23 § 8 Abs. 2 gehoert
    /// an genau eine Stelle), gemerkt wird hier.
    func overview(assumptions: [String: Double]) async throws -> GradesOverview {
        try await client.send("POST", "/api/overview",
                              body: AssumptionRequest(annahmen: assumptions))
    }

    /// Meldet das iPhone fuer Benachrichtigungen bei neuen Noten an.
    func registerDevice(token: String) async throws {
        let _: APIClient.Empty = try await client.send(
            "POST", "/api/devices", body: DeviceRegistration(token: token))
    }

    // MARK: - Koerper

    private struct Login: Encodable {
        let username: String
        let password: String
    }

    private struct LoginResponse: Decodable {
        let ok: Bool
    }

    private struct AssumptionRequest: Encodable {
        let annahmen: [String: Double]
    }

    private struct DeviceRegistration: Encodable {
        let token: String
    }
}

/// Woran der Zugang scheitert - die drei Faelle sehen fuer den Nutzer
/// verschieden aus und brauchen verschiedene Auswege.
enum GradesAccessProblem: Equatable, Sendable {
    /// 404: kein oder falscher Geraete-Token.
    case noDeviceToken
    /// 401: keine Sitzung. Kein Fehler - die App meldet sich dann selbst an.
    case notSignedIn
    /// Die Anmeldung selbst wurde abgelehnt.
    case wrongCredentials

    /// Ordnet einen Fehler der App-Schicht einem der drei Faelle zu.
    static func from(_ error: Error) -> GradesAccessProblem? {
        guard let apiError = error as? APIError else { return nil }
        switch apiError {
        case .http(404, _):    return .noDeviceToken
        case .http(401, _):    return .notSignedIn
        // nginx schickt Fremde auf die Startseite um; der private Bereich
        // sieht damit aus wie ein fehlender Geraete-Token, und der Ausweg
        // ist derselbe: Zugang pruefen.
        case .notAuthorised:   return .noDeviceToken
        default:               return nil
        }
    }
}
