import Foundation

/// Prueft einen persoenlichen Healthy-Token gegen **beide** Dienste, ohne etwas
/// zu speichern.
///
/// Gespeichert wird erst, wenn Kalorienzaehler und Weight Tracker ihn angenommen
/// haben - ein Token, der nur die Haelfte der App oeffnet, soll gar nicht erst
/// als eingerichtet gelten (wie in der Android-App, `core/Access.kt`).
///
/// Bewusst am `APIClient` vorbei: der zeigt ohne Netz den letzten Stand aus dem
/// `OfflineCache`, und eine alte Antwort darf einen neuen Token nicht
/// bestaetigen. Der Cookie haengt selbst an der Anfrage, der gemeinsame
/// Cookie-Speicher bleibt aus dem Spiel - sonst gewoenne der Privat-Cookie, der
/// auf Felix' iPhone daneben liegt, die Pruefung fuer jeden beliebigen Text.
enum HealthAccessCheck {

    enum Outcome: Equatable, Sendable {
        /// `name`: wem der Token gehoert (`me` des Kalorienzaehlers).
        case valid(token: String, name: String?)
        case invalid(String)
    }

    /// Was eine der beiden Anfragen ergeben hat.
    enum Probe: Equatable, Sendable {
        case accepted(Data)
        case denied
        case offline
        case failed(Int)
    }

    static func run(input: String, session: URLSession = .shared) async -> Outcome {
        guard let token = AccessToken.extract(input) else { return .invalid("Kein Token erkannt.") }
        async let food = probe(.food, path: "/api/food/features", token: token, session: session)
        async let weight = probe(.weight, path: "/api/weight/summary", token: token, session: session)
        return outcome(token: token, food: await food, weight: await weight)
    }

    /// Rein, damit die Regel ohne Netz pruefbar ist.
    static func outcome(token: String, food: Probe, weight: Probe) -> Outcome {
        for (backend, probe) in [(Backend.food, food), (Backend.weight, weight)] {
            switch probe {
            case .accepted: continue
            case .offline:  return .invalid("Kein Netz.")
            case .denied:   return .invalid("\(backend.title): Kein Zugang – Token prüfen.")
            case .failed(let code):
                return .invalid("\(backend.title): Der Dienst hat mit \(code) geantwortet.")
            }
        }
        guard case .accepted(let data) = food else { return .invalid("Kein Token erkannt.") }
        return .valid(token: token, name: name(from: data))
    }

    /// Ein Zugangsproblem sieht bei diesen Diensten nicht aus wie 401: 403 mit
    /// HTML, oder nach einer Weiterleitung eine Anmeldeseite mit 200.
    static func classify(status: Int, contentType: String?, body: Data) -> Probe {
        switch status {
        case 200..<300:
            let type = contentType?.lowercased() ?? ""
            return type.contains("json") ? .accepted(body) : .denied
        case 302, 401, 403:
            return .denied
        default:
            return .failed(status)
        }
    }

    static func name(from features: Data) -> String? {
        struct Me: Decodable { let me: String? }
        let name = (try? JSONDecoder().decode(Me.self, from: features))?.me?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private static func probe(_ backend: Backend, path: String, token: String,
                              session: URLSession) async -> Probe {
        var request = URLRequest(url: backend.url.appending(path: path))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.setValue("\(Keychain.healthTokenKey)=\(token)", forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline }
            return classify(status: http.statusCode,
                            contentType: http.value(forHTTPHeaderField: "Content-Type"), body: data)
        } catch {
            return .offline
        }
    }
}
