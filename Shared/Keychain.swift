import Foundation
import LocalAuthentication
import Security

/// Duenne Huelle um die Keychain-C-API - genug fuer zwei Zeichenketten.
///
/// Warum ueberhaupt Keychain und nicht `UserDefaults`: die beiden Token sind
/// Dauergeheimnisse (das Weight-Token gilt fuenf Jahre). `UserDefaults` landet
/// als lesbare Datei im App-Container und in jedem unverschluesselten Backup.
enum Keychain {

    /// Alles unter einem Dienst ablegen, damit `delete` gezielt raeumen kann.
    private static let service = "com.fherrmann.cockpit"

    /// Die Zugriffsgruppe, die alle drei Apps und ihre Erweiterungen teilen.
    ///
    /// Seit der Aufteilung in Healthy, Vault und Fokus eine eigene Gruppe:
    /// die Token werden einmal eingegeben und sind in allen Apps da. Jedes
    /// Target traegt sie in seinen Entitlements (project.yml).
    private static let accessGroup = "ZWFV263P59.com.fherrmann.shared"

    /// Die Gruppe von vorher - die Vorgabegruppe der einen App. Nur Healthy
    /// (dieselbe Bundle-ID) und ihre Kachel kommen noch heran; von dort
    /// wandern die Eintraege einmalig in die geteilte Gruppe
    /// (`Access.migrateToSharedGroup`).
    static let legacyAccessGroup = "ZWFV263P59.com.fherrmann.cockpit"

    /// Die Schluesselnamen stehen hier und nicht in `Access`: das Widget
    /// braucht sie, `Access` (WebKit, @MainActor) darf aber nicht mit in die
    /// Erweiterung.
    static let privateTokenKey = "fh_private"
    static let weightTokenKey = "weight_app_token"

    /// Der Geraete-Token der Notenuebersicht. Anderer Dienst, anderes
    /// Geheimnis - er gilt nur fuer `fherrmann.com/grades`.
    static let gradesTokenKey = "grades_token"
    /// Der Einkaufs-Token ist je Person - Felix' Freundin hat ihren eigenen,
    /// und der oeffnet nur die Einkaufsliste (docs/PLAN-AUFTEILUNG.md).
    static let shoppingTokenKey = "shopping_token"
    static let gradesUserKey = "grades_user"

    /// Das Passwort der Notenuebersicht. Als einziger Eintrag **hinter Face
    /// ID** - siehe `saveProtected`.
    static let gradesPasswordKey = "grades_password"

    static func save(_ value: String, for key: String) {
        // Erst loeschen: SecItemAdd scheitert an einem vorhandenen Eintrag,
        // und ein "Update" waere hier zwei Codepfade fuer nichts.
        delete(key)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            // Frueher `WhenUnlocked`. Ein Widget rendert und aktualisiert aber
            // bei GESPERRTEM Geraet - dort scheiterte jedes Lesen mit
            // errSecInteractionNotAllowed (-25308), und die Kachel behauptete
            // "Kein Zugang", obwohl der Zugang da ist. `AfterFirstUnlock`
            // heisst: ab dem ersten Entsperren nach einem Neustart lesbar.
            // Weiterhin nicht im Backup, weiterhin nicht synchronisiert.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String, group: String? = nil) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group ?? accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Hinter Face ID

    /// Legt einen Eintrag ab, den nur der Geraetebesitzer wieder herausbekommt.
    ///
    /// Fuer das Noten-Passwort. Die uebrigen Geheimnisse sind Geraete-Token:
    /// die braucht das Widget bei gesperrtem Bildschirm, eine Abfrage waere
    /// dort gar nicht moeglich. Das Passwort dagegen wird nur gebraucht, wenn
    /// Felix selbst vor dem Noten-Tab sitzt - und dann steht die Abfrage
    /// ohnehin an.
    ///
    /// `userPresence` heisst Face ID **oder** Gerätecode: dieselbe Wahl wie
    /// bei der Tab-Sperre. Nur Biometrie waere strenger, sperrte aber mit
    /// Maske oder nach drei Fehlversuchen aus.
    ///
    /// - Returns: `false`, wenn das Geraet gar keinen Code hat - dann gibt es
    ///   nichts, womit sich jemand ausweisen koennte.
    @discardableResult
    static func saveProtected(_ value: String, for key: String) -> Bool {
        delete(key)
        guard let data = value.data(using: .utf8),
              let control = SecAccessControlCreateWithFlags(
                nil,
                // Verschwindet, wenn der Code entfernt wird - was richtig ist:
                // ohne Code gibt es keine Huerde mehr, hinter der es liegen
                // koennte.
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .userPresence,
                nil)
        else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            // Statt kSecAttrAccessible - beides zusammen ist ein Widerspruch
            // und wird mit errSecParam abgelehnt.
            kSecAttrAccessControl as String: control,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Holt einen geschuetzten Eintrag heraus.
    ///
    /// ⚠️ **Nur mit einem bereits ausgewiesenen `LAContext` aufrufen.** Ohne
    /// ihn zeigt die Keychain die Abfrage selbst - und blockiert dabei den
    /// aufrufenden Faden, was auf dem Hauptfaden die Oberflaeche einfriert.
    /// Mit einem Kontext, der seine Pruefung hinter sich hat, faellt die
    /// Abfrage weg und der Aufruf kehrt sofort zurueck.
    static func readProtected(_ key: String, context: LAContext?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Ob ueberhaupt etwas hinterlegt ist - ohne den Inhalt zu holen und
    /// damit ohne Face-ID-Abfrage.
    static func hasProtected(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            // Ohne kSecReturnData bleibt der Inhalt verschlossen: die Keychain
            // beantwortet die Frage nach der blossen Existenz ohne Abfrage.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed heisst: es gibt ihn, er wollte nur
        // fragen. Fuer diese Frage ist das ein Ja.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
