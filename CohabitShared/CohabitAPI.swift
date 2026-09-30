import Foundation
import Observation

/// Was bei einer Anfrage an coHabit schiefgehen kann.
///
/// Anders als die uebrigen Dienste (siehe `APIClient`) antwortet coHabit
/// sauber: 401 heisst nicht angemeldet, alles andere ausserhalb von 2xx traegt
/// `{"message": "…"}` auf Deutsch - und genau die zeigt die App (Vertrag §3).
enum CohabitError: LocalizedError, Equatable {
    /// 401 - der Token gilt nicht (mehr).
    case unauthorized
    /// Der Dienst hat mit Begruendung abgelehnt (400, 403, 404, 409, 410, 413, 429, 5xx).
    case server(status: Int, message: String)
    /// Kein Netz, und kein letzter Stand, den man zeigen koennte.
    case offline
    /// Kein Netz - die Aenderung liegt im Postausgang. Fuer den Aufrufer ein Erfolg.
    case queued
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Kein Zugang – Link neu einfügen."
        case .server(_, let message): message
        case .offline: "Kein Netz."
        case .queued: "Kein Netz – geht raus, sobald wieder Netz da ist."
        case .decoding: "Die Antwort war nicht zu lesen."
        }
    }

    var status: Int? {
        if case .server(let status, _) = self { return status }
        if case .unauthorized = self { return 401 }
        return nil
    }
}

/// Die Anfragen an `fherrmann.com/cohabit/api` (Vertrag §3).
///
/// Der Token geht als Bearer an jede Anfrage - keine Cookies, weil die App
/// den Master-Token nie bekommt und die Kachel ohnehin keinen gemeinsamen
/// Cookie-Speicher hat. Lesende Antworten landen wie bei den anderen Apps im
/// `OfflineCache` und kommen ohne Netz von dort zurueck (mit Datum in der
/// Leiste, `CohabitSync`).
struct CohabitAPI: Sendable {

    var baseURL: URL
    var token: String?
    var timeout: TimeInterval
    var session: URLSession
    /// Ob Lesen ohne Netz auf den letzten Stand zurueckfaellt. Die Kachel und
    /// die Tests schalten das ab, wo es stoert.
    var usesCache: Bool

    init(token: String? = CohabitToken.load(),
         baseURL: URL = Backend.cohabit.url,
         timeout: TimeInterval = 30,
         session: URLSession = .shared,
         usesCache: Bool = true) {
        self.token = token
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
        self.usesCache = usesCache
    }

    // MARK: - Lesen und Schreiben

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(try await perform(request("GET", path, query: query)))
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: some Encodable & Sendable) async throws -> T {
        try decode(try await perform(request(method, path, body: body)))
    }

    /// Fuer Antworten ohne Inhalt (204) oder solche, deren Inhalt keiner braucht.
    func sendIgnoringResponse(_ method: String, _ path: String, body: (some Encodable & Sendable)? = Optional<EmptyBody>.none) async throws {
        _ = try await perform(request(method, path, body: body))
    }

    func delete<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(try await perform(request("DELETE", path, query: query)))
    }

    /// Rohdaten - Fotos und der Datenexport.
    func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var req = request("GET", path, query: query)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        return try await perform(req, cacheable: false)
    }

    /// Ein Foto hochladen (Vertrag §3.8). Der Schluessel macht das Hochladen
    /// wiederholbar: dieselbe Kennung noch einmal legt kein zweites Foto an.
    func uploadPhoto(jpeg: Data, key: String) async throws -> PhotoUpload {
        var req = multipartRequest("POST", "/photos", jpeg: jpeg)
        req.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        return try decode(try await perform(req))
    }

    /// Das Profilbild - quadratisch zugeschnitten hat es die App schon.
    func uploadAvatar(jpeg: Data) async throws -> MeView {
        try decode(try await perform(multipartRequest("PUT", "/me/avatar", jpeg: jpeg)))
    }

    // MARK: - Innereien

    struct EmptyBody: Codable, Sendable {}
    /// Fuer 204: ein Typ, der aus nichts dekodiert.
    struct Empty: Decodable, Sendable {}

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [],
                 body: (some Encodable)? = Optional<EmptyBody>.none) -> URLRequest {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Keine Cookies: ein fh_private aus einem gemeinsamen Speicher ginge
        // beim Dienst VOR einem fremden Cookie, aber nach dem Bearer - und
        // soll hier gar nicht erst mitlaufen.
        req.httpShouldHandleCookies = false
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? APIClient.encoder().encode(body)
        }
        return req
    }

    private func multipartRequest(_ method: String, _ path: String, jpeg: Data) -> URLRequest {
        var req = request(method, path)
        req.timeoutInterval = max(timeout, 90)
        let boundary = "cohabit-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.multipartBody(field: "photo", filename: "photo.jpg", mime: "image/jpeg",
                                          data: jpeg, boundary: boundary)
        return req
    }

    static func multipartBody(field: String, filename: String, mime: String, data: Data, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// Schickt ab und uebersetzt die Antwort. Lesen faellt ohne Netz auf den
    /// letzten Stand zurueck; Schreiben wirft `offline` - ob es in den
    /// Postausgang darf, entscheidet der Aufrufer (`CohabitOutbox`).
    func perform(_ request: URLRequest, cacheable: Bool = true) async throws -> Data {
        let isRead = request.httpMethod == "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error where OfflineCache.isOffline(error) {
            if isRead, cacheable, usesCache, let url = request.url, let cached = OfflineCache.load(for: url) {
                await CohabitSync.shared.servedFromCache(fetchedAt: cached.fetchedAt)
                return cached.data
            }
            throw CohabitError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw CohabitError.unauthorized }
            throw CohabitError.server(status: status, message: Self.message(from: data, status: status))
        }
        if isRead {
            await CohabitSync.shared.online()
            if cacheable, usesCache, let url = request.url { OfflineCache.store(data, for: url) }
        }
        // Der Dienst hat geantwortet, also ist Netz da - was wartet, darf raus.
        if await CohabitOutbox.shared.hasPending() {
            let api = self
            Task { await CohabitOutbox.shared.replay(using: api) }
        }
        return data
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == Empty.self, let empty = Empty() as? T { return empty }
        do {
            return try APIClient.decoder().decode(T.self, from: data)
        } catch {
            throw CohabitError.decoding(String(describing: error))
        }
    }

    /// Die Begruendung aus `{"message": "…"}` - sonst ein Satz mit dem Status.
    /// Eine HTML-Seite (nginx) gehoert nicht auf den Bildschirm.
    static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String,
           !message.trimmingCharacters(in: .whitespaces).isEmpty {
            return message
        }
        if let text = APIClient.shortMessage(from: data), !text.hasPrefix("{") { return text }
        switch status {
        case 413: return "Das Foto ist zu groß."
        case 429: return "Zu oft – später noch einmal."
        default: return "Der Dienst hat mit \(status) geantwortet."
        }
    }
}

/// Was die Oberflaeche ueber Netz und Postausgang wissen muss.
@MainActor
@Observable
final class CohabitSync {

    static let shared = CohabitSync()

    /// Gesetzt, solange gezeigte Daten aus dem Speicher kommen.
    private(set) var staleSince: Date?
    /// Aenderungen im Postausgang.
    private(set) var pending = 0
    /// Co-Habits mit einem wartenden Haken - dort zeigt der Knopf eine Uhr.
    private(set) var pendingCheckins: Set<String> = []
    /// Wartende Nachrichten je Co-Habit, fuer den Chat.
    private(set) var pendingMessages: [String: [MessageRequest]] = [:]
    /// Was der Dienst beim Nachsenden abgelehnt hat.
    private(set) var lastError: String?
    /// Zaehlt hoch, wenn der Postausgang leer geworden ist - die Bildschirme
    /// laden dann neu.
    private(set) var flushCount = 0

    private init() {}

    func servedFromCache(fetchedAt: Date) {
        staleSince = fetchedAt
    }

    func online() {
        staleSince = nil
    }

    func update(from entries: [CohabitOutbox.Entry], error: String?) {
        let before = pending
        pending = entries.count
        var checkins: Set<String> = []
        var messages: [String: [MessageRequest]] = [:]
        for entry in entries {
            switch entry.operation {
            case .checkin(let cohabitId, _): checkins.insert(cohabitId)
            case .message(let cohabitId, let request): messages[cohabitId, default: []].append(request)
            case .reaction: break
            }
        }
        pendingCheckins = checkins
        pendingMessages = messages
        if let error { lastError = error }
        if before > 0 && pending == 0 { flushCount += 1 }
    }

    func clearError() {
        lastError = nil
    }

    func reset() {
        staleSince = nil
        pending = 0
        pendingCheckins = []
        pendingMessages = [:]
        lastError = nil
    }
}
