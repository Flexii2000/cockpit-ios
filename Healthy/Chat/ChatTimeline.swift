import Foundation

/// Eine Frage, die die App abgeschickt hat und die der Dienst noch nicht kennt.
struct ChatPendingSend: Equatable, Identifiable, Sendable {
    let id: String
    let text: String
    /// Warum sie nicht ankam - `nil`: sie ist unterwegs.
    var failure: String? = nil
}

/// Eine Blase im Chat.
struct ChatBubble: Equatable, Identifiable {

    enum Kind: Equatable {
        /// Die eigene Frage, rechts.
        case question
        /// Die Antwort, links.
        case answer
        /// Die Antwort laeuft noch.
        case progress
        /// Nicht angekommen oder gescheitert - Tipp fragt noch einmal.
        case failed(ChatRetry)
    }

    let id: String
    let kind: Kind
    let text: String
}

/// Wie eine gescheiterte Frage noch einmal gestellt wird.
enum ChatRetry: Equatable {
    /// Sie kam beim Dienst nie an: mit **derselben** Kennung - kam sie doch an,
    /// liefert der Dienst den vorhandenen Stand, statt sie doppelt zu stellen.
    case resend(ChatPendingSend)
    /// Der Dienst hat sie angenommen und die Sitzung ist gescheitert: dieselbe
    /// Kennung gaebe nur den Fehler zurueck - also als neue Frage.
    case askAgain(question: String)
}

/// Das Gespraech als Folge von Blasen, und die Regeln drumherum - ohne SwiftUI,
/// damit sie sich pruefen lassen.
enum ChatTimeline {

    /// Die Blasen: je Frage die eigene rechts, darunter Antwort, Fortschritt
    /// oder Fehler. Was die App abgeschickt hat und der Dienst noch nicht
    /// kennt, steht am Ende - kennt er es schon, zaehlt sein Stand.
    static func bubbles(exchanges: [ChatExchange], sending: [ChatPendingSend]) -> [ChatBubble] {
        var bubbles: [ChatBubble] = []
        for exchange in exchanges {
            bubbles.append(ChatBubble(id: exchange.id + "-q", kind: .question, text: exchange.question))
            switch exchange.status {
            case .done:
                bubbles.append(ChatBubble(id: exchange.id + "-a", kind: .answer, text: exchange.answer ?? ""))
            case .failed:
                bubbles.append(ChatBubble(id: exchange.id + "-a",
                                          kind: .failed(.askAgain(question: exchange.question)),
                                          text: exchange.error ?? "Die Antwort ist ausgeblieben."))
            case .running, .unknown:
                bubbles.append(ChatBubble(id: exchange.id + "-a", kind: .progress, text: ""))
            }
        }
        let known = Set(exchanges.map(\.id))
        for pending in sending where !known.contains(pending.id) {
            bubbles.append(ChatBubble(id: pending.id + "-q", kind: .question, text: pending.text))
            if let failure = pending.failure {
                bubbles.append(ChatBubble(id: pending.id + "-a", kind: .failed(.resend(pending)), text: failure))
            } else {
                bubbles.append(ChatBubble(id: pending.id + "-a", kind: .progress, text: ""))
            }
        }
        return bubbles
    }

    /// Wie lange bis zur naechsten Abfrage (Vertrag §8.2): in den ersten 30
    /// Sekunden alle 1,5 s, danach alle 3 s, nach fuenf Minuten gar nicht mehr.
    static func pollDelay(elapsed: TimeInterval) -> TimeInterval? {
        if elapsed >= 300 { return nil }
        return elapsed < 30 ? 1.5 : 3
    }

    /// Ob eine Antwort dasteht, die noch niemand gesehen hat - der Knopf im
    /// Dashboard ist dann gefuellt.
    ///
    /// - Parameter seenThrough: bis zu welcher Antwort der Chat offen war.
    static func hasUnseenAnswer(_ exchanges: [ChatExchange], seenThrough: Date?) -> Bool {
        guard let latest = latestAnswer(exchanges) else { return false }
        guard let seenThrough else { return true }
        return latest > seenThrough
    }

    /// Wann die juengste fertige Antwort kam.
    static func latestAnswer(_ exchanges: [ChatExchange]) -> Date? {
        exchanges.filter { $0.status == .done }.compactMap(\.answeredAt).max()
    }

    /// Eine neue Kennung, wie der Dienst sie verlangt: UUID in Kleinbuchstaben.
    static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Was aus dem Eingabefeld wird: ohne Rand, und `nil`, wenn nichts dasteht.
    static func question(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Was unter einer Frage steht, die nicht ankam.
    static func failure(_ error: Error) -> String {
        if case APIError.offline = error { return "Kein Netz." }
        return "Nicht gesendet."
    }

    /// Ein Fehler als Satz - „Kein Netz.“ statt der langen Fassung des Systems.
    static func message(_ error: Error) -> String {
        if case APIError.offline = error { return "Kein Netz." }
        return error.localizedDescription
    }

    /// Was gesagt wird, wenn der Dienst eine Frage nicht annimmt.
    static func rejection(_ error: Error) -> String? {
        switch error {
        case APIError.http(409, _): "Eine Antwort läuft noch."
        case APIError.http(429, let message): message ?? "Für heute sind die Fragen aufgebraucht."
        case APIError.http(503, let message): message ?? "Claude ist gerade nicht erreichbar."
        case APIError.http(400, let message): message ?? "Die Frage konnte nicht gestellt werden."
        case APIError.notAuthorised: "Der Chat ist nicht freigeschaltet."
        default: nil
        }
    }
}
