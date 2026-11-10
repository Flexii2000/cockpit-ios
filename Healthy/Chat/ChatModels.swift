import Foundation

// Der Chat mit der Claude-Instanz auf dem Heimserver (Vertrag §8.2),
// abgeschrieben aus den Records unter `../weight-app/…/chat/dto/`. Der Dienst
// startet je Frage eine Sitzung, gibt ihr einen Auszug der Daten der Person mit
// und speichert Frage und Antwort - die App zeigt nur, was er liefert.

enum ChatStatus: String, LenientEnum {
    case running = "RUNNING"
    case done = "DONE"
    /// Mit `error` als kurzem deutschen Satz.
    case failed = "FAILED"
    case unknown
}

/// Eine Frage samt Antwort.
struct ChatExchange: Decodable, Equatable, Identifiable, Sendable {
    /// Die Kennung vergibt die App (UUID in Kleinbuchstaben) - dieselbe Frage
    /// zweimal geschickt stellt nichts doppelt.
    let id: String
    let question: String
    var askedAt: Date? = nil
    let status: ChatStatus
    /// Schlichter Text mit Absaetzen, hoechstens 4.000 Zeichen.
    var answer: String? = nil
    var answeredAt: Date? = nil
    var error: String? = nil
    var elapsedSeconds: Int? = nil
}

struct ChatLimits: Decodable, Equatable, Sendable {
    let perDay: Int
    let usedToday: Int
    let maxChars: Int
}

/// `GET /api/chat`.
struct ChatState: Decodable, Equatable, Sendable {
    /// Ob gerade gefragt werden kann (der Agent ist erreichbar).
    var available = true
    /// Aelteste zuerst.
    var exchanges: [ChatExchange] = []
    var limits: ChatLimits? = nil

    private enum CodingKeys: String, CodingKey { case available, exchanges, limits }

    init(available: Bool = true, exchanges: [ChatExchange] = [], limits: ChatLimits? = nil) {
        self.available = available
        self.exchanges = exchanges
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        exchanges = try container.decodeIfPresent([ChatExchange].self, forKey: .exchanges) ?? []
        limits = try container.decodeIfPresent(ChatLimits.self, forKey: .limits)
    }
}

/// Was die App an `POST /api/chat/messages` schickt.
struct ChatSend: Encodable, Equatable, Sendable {
    let id: String
    let text: String
}

struct ChatAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Das Gespraech. Auch die Abfrage, solange eine Antwort laeuft: immer
    /// dieselbe Adresse, damit ohne Netz der letzte Stand dasteht - eine Adresse
    /// je Frage legte fuer jede eine Datei in den Cache (`OfflineCache`). Der
    /// Dienst wertet beide Wege als „abgeholt“ (Vertrag §8.2).
    func state() async throws -> ChatState {
        try await client.get("/api/chat")
    }

    /// Stellt eine Frage: 202 mit `RUNNING`. 409 solange eine Antwort laeuft,
    /// 429 Tageslimit, 503 Agent nicht erreichbar.
    func ask(_ send: ChatSend) async throws -> ChatExchange {
        try await client.send("POST", "/api/chat/messages", body: send)
    }

    /// „Neuer Chat“ - eine noch laufende Antwort wird verworfen.
    func reset() async throws {
        let _: APIClient.Empty = try await client.delete("/api/chat")
    }
}
