import Foundation

struct ApprovalField: Codable, Hashable, Sendable {
    let name: String
    let wert: String
}

enum ApprovalStatus: String, Codable, Sendable {
    case wartet = "WARTET"
    case freigegeben = "FREIGEGEBEN"
    case ausgefuehrt = "AUSGEFUEHRT"
    case abgelehnt = "ABGELEHNT"
    case fehler = "FEHLER"
    case abgelaufen = "ABGELAUFEN"
    case unbekannt

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalStatus(rawValue: raw) ?? .unbekannt
    }

    var label: String {
        switch self {
        case .wartet: "Wartet"
        case .freigegeben: "Wird ausgeführt"
        case .ausgefuehrt: "Erledigt"
        case .abgelehnt: "Abgelehnt"
        case .fehler: "Fehlgeschlagen"
        case .abgelaufen: "Abgelaufen"
        case .unbekannt: "?"
        }
    }
}

struct ApprovalSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let art: String
    let titel: String
    let status: ApprovalStatus
    let erstellt: Date
    let erledigt: Date?
    let ergebnis: String?
}

struct ApprovalDetail: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let art: String
    let titel: String
    let status: ApprovalStatus
    let erstellt: Date
    let erledigt: Date?
    let ergebnis: String?
    let felder: [ApprovalField]
    let hash: String

    /// Selbst gerechnet - nur wenn er zum Server passt, laesst sich freigeben.
    var localHash: String { ApprovalPayload.hash(art: art, fields: felder) }
}

/// Ein Eintrag der Empfaengerliste fuer Ueberweisungen.
struct ApprovalRecipient: Codable, Identifiable, Hashable, Sendable {
    let iban: String
    let name: String
    let seit: Date
    let quelle: String

    var id: String { iban }

    /// "DE89 3704 0044 0532 0130 00"
    static func format(iban: String) -> String {
        let compact = iban.replacingOccurrences(of: " ", with: "").uppercased()
        return stride(from: 0, to: compact.count, by: 4).map { start in
            let from = compact.index(compact.startIndex, offsetBy: start)
            let to = compact.index(from, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            return String(compact[from..<to])
        }.joined(separator: " ")
    }
}

/// Das Gate des Assistenten (`fherrmann.com/assistant/api`), hinter dem
/// Privat-Cookie. Eigener kleiner Client statt `APIClient`: Freigaben duerfen
/// nie aus einem Offline-Zwischenstand kommen und nie in einen Postausgang.
struct ApprovalsAPI: Sendable {

    enum Failure: LocalizedError {
        case noAccess
        case server(Int, String?)

        var errorDescription: String? {
            switch self {
            case .noAccess: "Kein Zugang – Privat-Token fehlt oder ist falsch."
            case .server(let code, let message): message ?? "Server antwortete mit \(code)."
            }
        }
    }

    static let base = URL(string: "https://fherrmann.com/assistant/api")!

    let token: String
    var session: URLSession = .shared

    static func live() -> ApprovalsAPI? {
        Keychain.read(Keychain.privateTokenKey).map { ApprovalsAPI(token: $0) }
    }

    func list() async throws -> [ApprovalSummary] {
        try await send("GET", "freigaben")
    }

    func detail(id: String) async throws -> ApprovalDetail {
        try await send("GET", "freigaben/\(id)")
    }

    func approve(id: String, time: Int64, signature: Data) async throws -> ApprovalDetail {
        try await send("POST", "freigaben/\(id)/freigeben",
                       body: Signed(zeit: time, signatur: signature.base64EncodedString()))
    }

    func reject(id: String) async throws -> ApprovalDetail {
        try await send("POST", "freigaben/\(id)/ablehnen")
    }

    func recipients() async throws -> [ApprovalRecipient] {
        try await send("GET", "empfaenger")
    }

    func deleteRecipient(iban: String) async throws {
        let _: Empty = try await send("DELETE", "empfaenger/\(iban)")
    }

    func registerDevice(token deviceToken: String) async throws {
        let _: Empty = try await send("POST", "devices", body: Device(token: deviceToken))
    }

    private struct Signed: Encodable { let zeit: Int64; let signatur: String }
    private struct Device: Encodable { let token: String }
    private struct Empty: Decodable {}
    private struct ServerError: Decodable { let fehler: String }

    private func send<T: Decodable>(_ method: String, _ path: String,
                                    body: (any Encodable)? = nil) async throws -> T {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue("fh_private=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 204:
            return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        case 200..<300:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        case 302:
            throw Failure.noAccess
        case 403 where data.isEmpty || (try? JSONDecoder().decode(ServerError.self, from: data)) == nil:
            throw Failure.noAccess
        default:
            throw Failure.server(status, (try? JSONDecoder().decode(ServerError.self, from: data))?.fehler)
        }
    }
}
