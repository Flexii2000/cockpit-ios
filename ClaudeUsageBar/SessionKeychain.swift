import Foundation
import Security

/// Die claude.ai-Sitzung liegt **nur** im Schlüsselbund: ein Eintrag mit den Cookies
/// der Anmeldung (darunter der HttpOnly-Cookie `sessionKey…`). Die WebView selbst
/// hält sie nur im Speicher (`WKWebsiteDataStore.nonPersistent()`), es gibt also
/// keine Cookie-Datei auf der Platte, die ein anderes Programm lesen könnte.
///
/// Den Eintrag darf ohne Rückfrage nur diese App lesen (Zugriffsliste des
/// Schlüsselbunds, gebunden an die Signatur - darum signiert project.yml fest mit
/// dem Apple-Development-Zertifikat). Felix sieht und kopiert nie einen Token.
enum SessionKeychain {

    private static let service = "com.fherrmann.claudeusagebar"
    static let account = "claude.ai"

    /// Ein Cookie in speicherbarer Form - `HTTPCookie` selbst ist nicht `Codable`.
    struct StoredCookie: Codable, Equatable, Sendable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: Date?
        var secure: Bool
        var httpOnly: Bool
        var sameSite: String?

        init(_ cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path
            expires = cookie.expiresDate
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            sameSite = cookie.sameSitePolicy?.rawValue
        }

        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path,
            ]
            if let expires { properties[.expires] = expires }
            if secure { properties[.secure] = "TRUE" }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let sameSite { properties[.sameSitePolicy] = sameSite }
            return HTTPCookie(properties: properties)
        }
    }

    /// Blockiert, solange macOS nach dem Schlüsselbund fragt - nie auf dem Hauptthread.
    nonisolated static func load(account: String = account) -> [StoredCookie]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode([StoredCookie].self, from: data)
    }

    @discardableResult
    nonisolated static func save(_ cookies: [StoredCookie], account: String = account) -> Bool {
        guard let data = try? JSONEncoder().encode(cookies) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Erst ändern, nur wenn es den Eintrag nicht gibt anlegen: ein Löschen und
        // Neuanlegen setzte die Zugriffsliste zurück.
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "ClaudeUsageBar – claude.ai-Sitzung"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func delete(account: String = account) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
