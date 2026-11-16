import AppIntents
import Foundation

/// „Assistent fragen“ — die Aktion für den Action Button.
///
/// Ein Kurzbefehl „Text diktieren → Assistent fragen“ liegt auf dem Button: die
/// Frage geht an die zentrale Claude-Sitzung auf dem Heimserver, die Antwort
/// erscheint als Fenster. Dauert sie länger als `AssistantAsk.patience`, kommt
/// sie in Telegram — dort stehen Frage und Antwort immer mit, und dort geht ein
/// längeres Gespräch weiter (dieselbe Sitzung).
///
/// Läuft ohne die App zu öffnen. Ohne Wert fragt iOS selbst nach („Was soll ich
/// tun?“) — so geht es auch direkt als App-Kurzbefehl ohne eigenen Kurzbefehl.
struct AskAssistantIntent: AppIntent {

    static let title: LocalizedStringResource = "Assistent fragen"
    static let description = IntentDescription(
        "Schickt eine Frage oder einen Auftrag an den Assistenten auf dem Heimserver und zeigt die Antwort. Dauert es länger, kommt die Antwort in Telegram.")
    static let openAppWhenRun = false

    @Parameter(title: "Frage", requestValueDialog: IntentDialog("Was soll ich tun?"))
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw $question.needsValueError("Was soll ich tun?")
        }
        guard let token = Keychain.read(Keychain.privateTokenKey) else {
            throw AssistantAsk.Failure.noAccess
        }
        let reply = switch try await AssistantAsk.live(token: token).run(text) {
        case .answered(let answer): answer
        case .stillRunning: AssistantAsk.stillRunningText
        }
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}
