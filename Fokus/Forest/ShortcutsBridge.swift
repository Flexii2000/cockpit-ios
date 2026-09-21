import UIKit

/// Ruft Felix' Kurzbefehle „Fokus an" und „Fokus aus" auf - die schalten den
/// Fokus-Modus des Handys (Mitteilungen aus) ein und aus.
///
/// Warum ueber Kurzbefehle: eine App darf den Fokus-Modus des Systems nicht
/// selbst schalten. Ein Kurzbefehl darf es, und ihn kann die App per
/// x-callback-URL anstossen. Die Kurzbefehle-App springt dabei kurz auf und
/// kommt ueber `cockpit-fokus://forest` zurueck.
///
/// Der Aufruf geht nur aus dem Vordergrund. „Fokus aus" kommt deshalb, sobald
/// die App nach dem Ende der Session wieder offen ist - meist ueber den Tipp
/// auf die Meldung „Baum gepflanzt". Wer den Fokus-Modus punktgenau am Ende
/// aus haben will, baut „Fokus an" mit dem uebergebenen Endzeitpunkt
/// („Fokus einschalten bis …"); der kommt als Eingabe mit.
///
/// Die Rueckkehr traegt, was passiert ist: `?shortcut=an&result=ok|error|cancel`,
/// bei einem Fehler haengt Kurzbefehle `errorMessage` an - so steht in der
/// App, dass etwa „Fokus an" gar nicht existiert, statt dass Kurzbefehle
/// stumm zurueckspringt.
@MainActor
enum ShortcutsBridge {

    nonisolated static let onName = "Fokus an"
    nonisolated static let offName = "Fokus aus"
    nonisolated static let callback = "cockpit-fokus://forest"

    enum Result: String {
        case ok, error, cancel
    }

    /// Was eine Rueckkehr-URL sagt: welcher Kurzbefehl, wie es ausging, und
    /// Kurzbefehles eigene Fehlermeldung. Nil fuer jede andere URL.
    struct Return {
        let name: String
        let result: Result
        let message: String?

        init?(url: URL) {
            guard url.host() == "forest",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let which = items.first(where: { $0.name == "shortcut" })?.value,
                  let raw = items.first(where: { $0.name == "result" })?.value,
                  let result = Result(rawValue: raw)
            else { return nil }
            name = which == "aus" ? ShortcutsBridge.offName : ShortcutsBridge.onName
            self.result = result
            message = items.first { $0.name == "errorMessage" }?.value
        }

        /// Die Zeile fuer die Leiste - nil, wenn alles gut ging.
        var note: String? {
            switch result {
            case .ok:     nil
            case .cancel: "Kurzbefehl „\(name)“ abgebrochen."
            case .error:  "Kurzbefehl „\(name)“: \(message ?? "Fehler ohne Meldung")"
            }
        }
    }

    private static let enabledKey = "forest.shortcutsEnabled"

    /// Aus, wenn die Kurzbefehle (noch) nicht existieren - sonst meldet die
    /// Kurzbefehle-App bei jeder Session einen Fehler.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// „Fokus an" mit der Restdauer in **Minuten** als Text-Eingabe („30").
    /// Liefert, ob die Kurzbefehle-App wirklich aufging - dann verlaesst
    /// die App den Vordergrund und der Aufrufer wartet mit dem Schild.
    @discardableResult
    static func focusOn(until end: Date) async -> Bool {
        await run(onName, tag: "an", input: inputText(for: end))
    }

    /// Minuten statt eines Datums: ein Datum als Text muss der Kurzbefehl
    /// erst lesen - Format, Sprache, Zeitzone, und beim Testbaum lag die
    /// Zeit ohne Sekunden schon in der Vergangenheit, was der Fokus als „bis
    /// morgen" nahm. Eine Zahl kennt keinen dieser Fehler; der Kurzbefehl
    /// zaehlt sie mit „Datum anpassen" auf das aktuelle Datum. Aufgerundet
    /// und mindestens eine: lieber eine Minute laenger still als zu kurz.
    static func inputText(for end: Date, now: Date = Date()) -> String {
        let minutes = Int(ceil(max(0, end.timeIntervalSince(now)) / 60))
        return String(max(1, minutes))
    }

    @discardableResult
    static func focusOff() async -> Bool {
        await run(offName, tag: "aus", input: nil)
    }

    private static func run(_ name: String, tag: String, input: String?) async -> Bool {
        guard isEnabled, let url = url(for: name, tag: tag, input: input) else { return false }
        return await UIApplication.shared.open(url)
    }

    static func url(for name: String, tag: String, input: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        var items = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "\(callback)?shortcut=\(tag)&result=ok"),
            URLQueryItem(name: "x-error", value: "\(callback)?shortcut=\(tag)&result=error"),
            URLQueryItem(name: "x-cancel", value: "\(callback)?shortcut=\(tag)&result=cancel"),
        ]
        if let input {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        return components.url
    }
}
