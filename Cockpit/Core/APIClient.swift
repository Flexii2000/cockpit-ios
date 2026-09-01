import Foundation

enum APIError: LocalizedError {
    case notAuthorised
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorised:
            "Kein Zugang - Token prüfen."
        case .http(let code):
            "Der Dienst hat mit \(code) geantwortet."
        case .decoding:
            "Die Antwort war nicht zu lesen."
        }
    }
}

/// Schmaler HTTP-Client fuer die beiden JSON-Backends.
///
/// Die Cookies kommen aus `HTTPCookieStorage.shared`, den `URLSession.shared`
/// von sich aus benutzt - deshalb steht hier nichts ueber Authentifizierung.
/// Gesetzt werden sie beim App-Start in `Access.applyCookies()`.
struct APIClient: Sendable {

    let backend: Backend
    /// Grosszuegig, weil die Schnellerfassung des Kalorienzaehlers eine
    /// Claude-Session auf dem Server startet: gemessen wurden bis zu 56 s,
    /// serverseitig darf sie 180 s dauern.
    var timeout: TimeInterval = 200

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await perform(request(method: "GET", path: path, query: query))
    }

    func send<Body: Encodable, T: Decodable>(
        _ method: String, _ path: String, body: Body
    ) async throws -> T {
        var req = request(method: method, path: path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await perform(req)
    }

    @discardableResult
    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(method: "DELETE", path: path))
    }

    // MARK: - Innereien

    private func request(method: String, path: String,
                         query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(
            url: backend.url.appending(path: path),
            resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.timeoutInterval = timeout
        // Ohne gueltiges Cookie antworten beide Backends mit einer HTML-Seite
        // statt mit JSON. Das hier macht die Absicht wenigstens klar.
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // Fehlender Zugang sieht bei diesen Diensten nicht aus wie 401: der
        // Kalorienzaehler wird von nginx per 302 auf fherrmann.com geschickt,
        // beide Apps antworten sonst mit 403 und HTML. Alles ausserhalb von
        // 2xx deshalb als Zugangsproblem behandeln und gar nicht erst
        // versuchen, es als JSON zu lesen.
        guard (200..<300).contains(status) else {
            throw status == 403 || status == 302 ? APIError.notAuthorised : APIError.http(status)
        }
        if T.self == Empty.self, let empty = Empty() as? T { return empty }
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Antworten ohne Inhalt (204) brauchen trotzdem einen Rueckgabetyp.
    struct Empty: Decodable, Sendable {}

    /// `LocalDate` wird von `CalendarDate` selbst gelesen; hier bleibt nur
    /// `Instant` (z. B. `FoodEntry.createdAt`). Jackson haengt daran je nach
    /// Wert bis zu neun Nachkommastellen - mehr, als `ISO8601DateFormatter`
    /// verkraftet. Deshalb wird der Bruchteil abgeschnitten, bevor geparst
    /// wird; Nanosekunden braucht hier ohnehin niemand.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseInstant(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Kein ISO-Zeitpunkt: \(raw)"))
            }
            return date
        }
        return decoder
    }

    static func parseInstant(_ raw: String) -> Date? {
        var text = raw
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" }) {
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
