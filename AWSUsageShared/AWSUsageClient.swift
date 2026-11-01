import Foundation

/// Spricht den Dienst `aws-usage` (`fherrmann.com/aws-usage`) - in Vault und in
/// der Menüleisten-App derselbe Client.
///
/// Mit Bearer statt Cookie: die Mac-App hat keinen `Access`, der Cookies legt,
/// und der Dienst nimmt beides. Kein `APIClient` aus `Shared/` - den gibt es auf
/// dem Mac nicht; Offline-Stand und Leiste macht Vault in seinem Store selbst.
struct AWSUsageClient: Sendable {

    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    /// Holt den Stand. Die rohen Bytes kommen mit, damit Vault sie in den
    /// `OfflineCache` legen kann.
    func usage() async throws -> (usage: AWSUsage, data: Data) {
        let data = try await perform(request("GET", "api/usage"))
        return (try decode(data), data)
    }

    /// Ändert das AWS-Budget; der Dienst antwortet mit dem neuen Stand.
    func setBudget(limit: Double) async throws -> (usage: AWSUsage, data: Data) {
        var req = request("PUT", "api/budget")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["limit": limit])
        let data = try await perform(req)
        return (try decode(data), data)
    }

    /// Meldet Vault für die Budget-Pushes an (Topic `com.fherrmann.vault`).
    func registerDevice(token deviceToken: String) async throws {
        var req = request("POST", "api/devices")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["token": deviceToken])
        _ = try await perform(req)
    }

    /// Die Adresse von `GET /api/usage` - unter ihr legt Vault den Offline-Stand ab.
    var usageURL: URL { baseURL.appending(path: "api/usage") }

    // MARK: - Innereien

    private func request(_ method: String, _ path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Sonst ginge in Vault zusätzlich das Privat-Cookie mit - doppelt, und
        // bei einem veralteten Cookie widerspräche es dem Bearer.
        req.httpShouldHandleCookies = false
        return req
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if AWSUsageError.isOffline(error) { throw AWSUsageError.offline }
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 302, 401, 403:
            throw AWSUsageError.notAuthorised
        case 503:
            throw AWSUsageError.unavailable(Self.message(in: data))
        default:
            throw AWSUsageError.http(status, Self.message(in: data))
        }
    }

    private func decode(_ data: Data) throws -> AWSUsage {
        do {
            return try AWSUsageCoding.decoder().decode(AWSUsage.self, from: data)
        } catch {
            throw AWSUsageError.decoding
        }
    }

    /// `{"error": "..."}` des Dienstes, sonst kurzer Klartext; HTML nie.
    static func message(in data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["error"] as? String, !text.isEmpty {
            return text
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("{"), text.count <= 300
        else { return nil }
        return text
    }
}

enum AWSUsageError: LocalizedError, Equatable {
    case notAuthorised
    /// 503: seit dem Start des Dienstes ist noch kein Abruf bei AWS gelungen.
    case unavailable(String?)
    case http(Int, String?)
    case decoding
    case offline

    var errorDescription: String? {
        switch self {
        case .notAuthorised: "Kein Zugang – fh_private prüfen."
        case .unavailable(let message): message ?? "Noch keine Zahlen von AWS."
        case .http(let code, let message): message ?? "Der Dienst hat mit \(code) geantwortet."
        case .decoding: "Die Antwort war nicht zu lesen."
        case .offline: "Kein Netz."
        }
    }

    /// Dieselben Fälle wie `OfflineCache.isOffline` in den iPhone-Apps.
    static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                .cannotConnectToHost, .timedOut, .dnsLookupFailed,
                .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed].contains(error.code)
    }
}

/// Wo der Dienst liegt.
enum AWSUsageEndpoint {

    static var url: URL {
        #if DEBUG
        // Wie `Backend.url` in den iPhone-Apps: COCKPIT_URL_AWS biegt auf einen
        // lokal laufenden Dienst oder Schein-Server um.
        if let override = ProcessInfo.processInfo.environment["COCKPIT_URL_AWS"],
           !override.isEmpty, let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://fherrmann.com/aws-usage")!
    }
}
