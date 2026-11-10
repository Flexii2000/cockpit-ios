import Foundation

/// Eine eigene Nachricht im Rezept-Chat, die die App schon zeigt, bevor der Dienst
/// sie bestaetigt hat. Die Kennung vergibt die App (kleingeschriebene UUID) -
/// dieselbe noch einmal haengt beim Dienst nichts an.
struct ShoppingChatPending: Equatable, Sendable {
    let id: String
    let text: String
}

/// Eine Zeile im Rezept-Chat.
enum ShoppingChatRow: Equatable, Identifiable, Sendable {
    case message(ShoppingChatMessage)
    /// Die eigene Nachricht auf dem Weg zum Dienst.
    case sending(ShoppingChatPending)
    /// Die Antwort entsteht.
    case typing
    /// Es kam keine Antwort - mit dem Satz des Dienstes, falls er einen schickt.
    /// Darunter bietet die Ansicht „Erneut senden“ an.
    case failed(message: String?)

    /// Die wartende und die bestaetigte Fassung derselben Nachricht teilen sich die
    /// Kennung - die Blase bleibt beim Wechsel stehen, statt zu springen.
    var id: String {
        switch self {
        case .message(let message): message.id
        case .sending(let pending): pending.id
        case .typing: "typing"
        case .failed: "failed"
        }
    }
}

/// Was der Rezept-Chat zeigt: das Gespraech, wie der Dienst es fuehrt, und darunter,
/// was die App darueber hinaus weiss - die eigene Nachricht unterwegs, dass eine
/// Antwort entsteht, oder dass keine kam.
///
/// Das Gespraech selbst liegt nur beim Dienst; die App merkt sich nichts davon.
enum ShoppingChatTimeline {

    /// - Parameters:
    ///   - pending: die Nachricht, die gerade gesendet wird oder deren Senden scheiterte
    ///   - sendError: warum das Senden scheiterte (kein Netz, Tageslimit …)
    ///   - stalled: die Nachfrage hat aufgegeben, obwohl der Dienst noch „laeuft“ meldet
    static func rows(chat: ShoppingChat?, pending: ShoppingChatPending?, sendError: String?,
                     stalled: Bool) -> [ShoppingChatRow] {
        let messages = chat?.messages ?? []
        var rows = messages.map(ShoppingChatRow.message)
        if let pending, !messages.contains(where: { $0.id == pending.id }) {
            rows.append(.sending(pending))
        }
        if let sendError {
            if pending != nil { rows.append(.failed(message: sendError)) }
            return rows
        }
        if pending != nil {
            // Unterwegs zum Dienst - gleich laeuft dort die Antwort.
            rows.append(.typing)
            return rows
        }
        guard let chat else { return rows }
        if let job = chat.job, job.isRunning {
            rows.append(stalled ? .failed(message: nil) : .typing)
        } else if let job = chat.job, job.isFailed {
            rows.append(.failed(message: job.error))
        } else if chat.unanswered != nil {
            // Der Dienst lief neu, waehrend die Antwort entstand: die Frage steht
            // ohne Antwort da, und nichts laeuft mehr.
            rows.append(.failed(message: nil))
        }
        return rows
    }

    /// Ob gerade eine Antwort entsteht - dann ist das Eingabefeld gesperrt (der
    /// Dienst nimmt je Person nur eine offene Frage an).
    static func isBusy(chat: ShoppingChat?, pending: ShoppingChatPending?, sendError: String?,
                       stalled: Bool) -> Bool {
        if pending != nil { return sendError == nil }
        return chat?.job?.isRunning == true && !stalled
    }

    /// Was „Erneut senden“ schickt: die eigene Nachricht, deren Senden scheiterte,
    /// sonst die letzte eigene im Gespraech - mit derselben Kennung, damit der Dienst
    /// nur die Antwort neu anfordert.
    static func retry(chat: ShoppingChat?, pending: ShoppingChatPending?) -> ShoppingChatPending? {
        if let pending { return pending }
        guard let last = chat?.messages.last(where: \.isMine) else { return nil }
        return ShoppingChatPending(id: last.id, text: last.text)
    }
}
