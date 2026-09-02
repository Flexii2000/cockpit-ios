import Foundation
import Security

/// Duenne Huelle um die Keychain-C-API - genug fuer zwei Zeichenketten.
///
/// Warum ueberhaupt Keychain und nicht `UserDefaults`: die beiden Token sind
/// Dauergeheimnisse (das Weight-Token gilt fuenf Jahre). `UserDefaults` landet
/// als lesbare Datei im App-Container und in jedem unverschluesselten Backup.
enum Keychain {

    /// Alles unter einem Dienst ablegen, damit `delete` gezielt raeumen kann.
    private static let service = "com.fherrmann.cockpit"

    /// Die geteilte Zugriffsgruppe.
    ///
    /// Sie ist die **Vorgabegruppe der App** (Team-Praefix + Bundle-ID) - die
    /// vorhandenen Eintraege liegen also bereits darin, es zieht nichts um.
    /// Die Widget-Erweiterung hat eine andere Bundle-ID und kaeme ohne das
    /// Entitlement nicht heran.
    private static let accessGroup = "ZWFV263P59.com.fherrmann.cockpit"

    /// Die Schluesselnamen stehen hier und nicht in `Access`: das Widget
    /// braucht sie, `Access` (WebKit, @MainActor) darf aber nicht mit in die
    /// Erweiterung.
    static let privateTokenKey = "fh_private"
    static let weightTokenKey = "weight_app_token"

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

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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
