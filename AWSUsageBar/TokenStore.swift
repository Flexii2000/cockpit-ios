import Foundation
import Security

/// Woher die Menüleisten-App den Privat-Token nimmt.
///
/// Zuerst ein eigener Eintrag - den legt nur das Eingabefeld an, er ist also
/// eine ausdrückliche Wahl. Sonst der Eintrag, den `tools/run-simulator.sh`
/// schon nutzt (Dienst `fh_private`, Konto `cockpit-ios`). Für den fragt macOS
/// beim ersten Lesen nach („Immer erlauben“); das hält, solange die App mit
/// demselben Zertifikat signiert ist (project.yml).
enum TokenStore {

    private static let sharedService = "fh_private"
    private static let sharedAccount = "cockpit-ios"
    private static let ownService = "com.fherrmann.awsusagebar"
    private static let ownAccount = "fh_private"

    /// Blockiert, solange die Schlüsselbund-Abfrage offen ist - deshalb nie auf
    /// dem Hauptthread aufrufen.
    nonisolated static func read() -> String? {
        #if DEBUG
        // Gegen einen Schein-Server oder lokalen Dienst - ohne den echten Token
        // aus dem Schlüsselbund zu berühren.
        if let value = ProcessInfo.processInfo.environment["COCKPIT_FH_PRIVATE_TOKEN"], !value.isEmpty {
            return value
        }
        #endif
        return read(service: ownService, account: ownAccount)
            ?? read(service: sharedService, account: sharedAccount)
    }

    @discardableResult
    nonisolated static func save(_ token: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrLabel as String] = "AWSUsageBar fh_private"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func deleteOwn() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount,
        ] as CFDictionary)
    }

    private nonisolated static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }
}
