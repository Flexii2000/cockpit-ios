import Foundation

/// Wie weit das Morgen-Briefing von heute ist (Vertrag §8.3).
enum BriefingStatus: String, LenientEnum {
    /// Heute hat noch niemand eins angefordert.
    case none = "NONE"
    /// Die Sitzung schreibt gerade - ein aelterer Text von heute steht solange weiter da.
    case running = "RUNNING"
    case done = "DONE"
    /// Der Lauf ist gescheitert; der naechste `POST` wiederholt ihn, solange
    /// von den drei Laeufen des Tages noch einer uebrig ist.
    case failed = "FAILED"
    case unknown
}

/// Das Morgen-Briefing (`GET`/`POST /api/briefing/today`): zwei bis drei Saetze
/// aus der Claude-Sitzung auf dem Server - die Nacht, wie gestern lief, was
/// heute passt.
struct Briefing: Decodable, Equatable, Sendable {
    var date: CalendarDate? = nil
    let status: BriefingStatus
    var text: String? = nil
    var generatedAt: Date? = nil
}

struct BriefingAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Der Stand von heute - loest nie etwas aus.
    func today() async throws -> Briefing {
        try await client.get("/api/briefing/today")
    }

    /// Fordert das Briefing von heute an. Idempotent: gibt es schon eins, kommt
    /// es zurueck; kam seither eine Nacht dazu, schreibt der Dienst es einmal neu.
    func ensure() async throws -> Briefing {
        try await client.send("POST", "/api/briefing/today")
    }
}

/// Was die Karte zeigt, wenn der Dienst etwas gemeldet hat - als reine Regel,
/// damit sie sich pruefen laesst.
enum BriefingRule {

    /// - Parameters:
    ///   - shown: der Text, der gerade dasteht (von heute), oder `nil`.
    ///   - briefing: die Antwort des Dienstes.
    /// - Returns: der Text, der danach dasteht. Ein neuer Text ersetzt den
    ///   alten; ohne Text bleibt der alte stehen - waehrend der Dienst neu
    ///   schreibt (`RUNNING`), und auch wenn der neue Lauf scheitert: dann gilt
    ///   beim Dienst der alte weiter (Vertrag §8.3).
    static func text(shown: String?, after briefing: Briefing) -> String? {
        if let fresh = briefing.text?.trimmingCharacters(in: .whitespacesAndNewlines), !fresh.isEmpty {
            return fresh
        }
        return shown
    }

    /// Wie oft bei `RUNNING` nachgefragt wird, und wie lange hoechstens.
    static let pollSeconds = 5.0
    static let pollLimitSeconds = 120.0
}

/// Der Text von heute, gemerkt ueber den Start der App hinweg - die Karte
/// steht dann sofort da und nicht erst nach dem Abgleich.
struct BriefingMemory: Codable, Equatable, Sendable {
    let date: CalendarDate
    let text: String

    /// Nur der Text von heute zaehlt; gestern ist kein Briefing mehr.
    static func text(in data: Data?, today: CalendarDate) -> String? {
        guard let data, let memory = try? JSONDecoder().decode(BriefingMemory.self, from: data),
              memory.date == today, !memory.text.isEmpty else { return nil }
        return memory.text
    }

    static func data(text: String, today: CalendarDate) -> Data? {
        try? JSONEncoder().encode(BriefingMemory(date: today, text: text))
    }
}
