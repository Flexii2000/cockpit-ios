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

    static func save(_ value: String, for key: String) {
        // Erst loeschen: SecItemAdd scheitert an einem vorhandenen Eintrag,
        // und ein "Update" waere hier zwei Codepfade fuer nichts.
        delete(key)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Ohne Geraetesperre kein Zugriff, und nichts davon wandert in ein
            // Backup oder auf ein anderes Geraet.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
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
        ]
        SecItemDelete(query as CFDictionary)
    }
}
