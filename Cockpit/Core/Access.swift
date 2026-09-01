import Foundation
import WebKit

/// Haelt die beiden Zugangstoken und macht daraus Cookies.
///
/// Die Backends kennen ausschliesslich Cookie-Auth (siehe docs/BACKENDS.md).
/// Im Browser stellt man die Cookies einmal pro Geraet ueber `/setup?token=…`
/// aus; die App spart sich das Ritual und setzt sie direkt. Sie muessen in
/// ZWEI Speicher, sonst funktioniert jeweils die eine Haelfte der App nicht:
///
/// * `WKWebsiteDataStore.default()` - fuer die WebView-Tabs
/// * `HTTPCookieStorage.shared`     - fuer die `URLSession` der nativen Tabs
@MainActor
@Observable
final class Access {

    static let privateTokenKey = "fh_private"
    static let weightTokenKey = "weight_app_token"

    private(set) var privateToken: String?
    private(set) var weightToken: String?

    /// Ohne beide Token bleibt die App leer - dann zeigt `RootView` die
    /// Einrichtung, statt drei Tabs mit Fehlermeldungen anzubieten.
    var isConfigured: Bool { privateToken != nil && weightToken != nil }

    init() {
        privateToken = Keychain.read(Self.privateTokenKey)
        weightToken = Keychain.read(Self.weightTokenKey)
    }

    func store(privateToken: String, weightToken: String) async {
        let p = privateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = weightToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(p, for: Self.privateTokenKey)
        Keychain.save(w, for: Self.weightTokenKey)
        self.privateToken = p
        self.weightToken = w
        await applyCookies()
    }

    func reset() {
        Keychain.delete(Self.privateTokenKey)
        Keychain.delete(Self.weightTokenKey)
        privateToken = nil
        weightToken = nil
    }

    /// Muss laufen, BEVOR eine WebView laedt oder eine API-Anfrage rausgeht.
    func applyCookies() async {
        var cookies: [HTTPCookie] = []
        // Domain mit fuehrendem Punkt: das Privat-Token gilt fuer alle
        // Subdomains von fherrmann.com, genau wie das Cookie, das
        // fherrmann.com/setup ausstellt.
        if let privateToken, let c = Self.cookie(name: Self.privateTokenKey,
                                                 value: privateToken,
                                                 domain: ".fherrmann.com") {
            cookies.append(c)
        }
        // Das Weight-Token gehoert genau einer Domain - kein Grund, es
        // breiter zu streuen als noetig.
        if let weightToken, let c = Self.cookie(name: Self.weightTokenKey,
                                                value: weightToken,
                                                domain: "weight.fherrmann.com") {
            cookies.append(c)
        }
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
            await store.setCookie(cookie)
        }
    }

    private static func cookie(name: String, value: String, domain: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
            .secure: "TRUE",
            // Ein Jahr. Die Token selbst leben laenger; laeuft das Cookie doch
            // einmal ab, setzt der naechste App-Start es neu aus dem Keychain.
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
        ])
    }
}
