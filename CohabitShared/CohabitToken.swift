import Foundation

/// Der Token der angemeldeten Person.
///
/// Im Schluesselbund, in einer eigenen Zugriffsgruppe, die nur coHabit, seine
/// Kachel und die Notification Service Extension tragen (project.yml) - die
/// Kachel holt sich ihren Stand selbst, die Erweiterung das Bild einer
/// Benachrichtigung, und keine der anderen Apps braucht diesen Token.
///
/// Eine eigene Datei, weil die Erweiterung nur sie (samt `Keychain`)
/// uebersetzt und nicht den Rest von `CohabitShared`. Gespeichert wird
/// er erst, wenn `GET /me` damit 200 geliefert hat (Vertrag §5.4).
enum CohabitToken {

    static let key = "cohabit_token"
    static let group = "ZWFV263P59.com.fherrmann.cohabit"

    static func load() -> String? {
        guard let value = Keychain.read(key, group: group), !value.isEmpty else { return nil }
        return value
    }

    static func save(_ token: String) {
        Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: key, group: group)
    }

    static func clear() {
        Keychain.delete(key, group: group)
    }

    #if DEBUG
    /// Nur fuer Simulator und UI-Tests: `COCKPIT_COHABIT_TOKEN` legt den
    /// Token ab, als waere ein Link eingefuegt worden; `none` nimmt ihn weg
    /// (Start ohne Zugang - der Schluesselbund ueberlebt sonst jede
    /// Neuinstallation). Auf dem Geraet setzt niemand Umgebungsvariablen.
    /// - Returns: ob sich der Token dadurch geaendert hat.
    @discardableResult
    static func seedFromEnvironment() -> Bool {
        guard let value = ProcessInfo.processInfo.environment["COCKPIT_COHABIT_TOKEN"], !value.isEmpty else { return false }
        let before = load()
        if value == "none" {
            clear()
        } else {
            save(value)
        }
        return load() != before
    }
    #endif
}
