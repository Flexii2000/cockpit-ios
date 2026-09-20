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
@MainActor
enum ShortcutsBridge {

    static let onName = "Fokus an"
    static let offName = "Fokus aus"
    static let callback = "cockpit-fokus://forest"

    private static let enabledKey = "forest.shortcutsEnabled"

    /// Aus, wenn die Kurzbefehle (noch) nicht existieren - sonst meldet die
    /// Kurzbefehle-App bei jeder Session einen Fehler.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// „Fokus an" mit dem Endzeitpunkt als Text-Eingabe (`2026-09-20 21:45`).
    static func focusOn(until end: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        run(onName, input: formatter.string(from: end))
    }

    static func focusOff() {
        run(offName, input: nil)
    }

    private static func run(_ name: String, input: String?) {
        guard isEnabled, let url = url(for: name, input: input) else { return }
        UIApplication.shared.open(url)
    }

    static func url(for name: String, input: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        var items = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: callback),
            URLQueryItem(name: "x-error", value: callback),
            URLQueryItem(name: "x-cancel", value: callback),
        ]
        if let input {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        return components.url
    }
}
