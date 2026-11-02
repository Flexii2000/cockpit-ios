import Foundation
import WebKit

/// Der Weg zu claude.ai: eine unsichtbare WebView statt `URLSession`.
///
/// Warum WebKit: claude.ai steht hinter Cloudflare. Eine echte Browser-Engine mit
/// denselben Cookies und derselben Kennung wie bei der Anmeldung besteht dessen
/// Prüfungen von selbst; ein nachgebauter Request mit kopiertem Cookie-Kopf (so
/// macht es die Claude Usage Bar) nicht immer. Gefragt wird mit `fetch` aus einer
/// claude.ai-Seite heraus - genau so, wie die Seite „Einstellungen > Nutzung“ es tut.
///
/// Die Cookies leben nur im Speicher (`nonPersistent`) und im Schlüsselbund
/// (`SessionKeychain`), nie in einer Datei.
@MainActor
final class ClaudeWeb: NSObject, WKNavigationDelegate {

    enum Failure: Error, Equatable {
        /// claude.ai kennt die Sitzung nicht (mehr) - neu anmelden.
        case signedOut
        /// Cloudflare will eine Prüfung sehen, die die unsichtbare WebView nicht
        /// besteht - im Anmeldefenster (sichtbar) geht sie durch.
        case challenged
        case http(Int)
        case unreachable(String)
    }

    static let base = URL(string: "https://claude.ai")!
    static let loginURL = URL(string: "https://claude.ai/login")!
    /// Die Seite, aus der heraus gefragt wird: klein (JSON, kein Skript der Seite)
    /// und vom selben Ursprung wie die Schnittstelle.
    private static let anchorURL = URL(string: "https://claude.ai/api/organizations")!
    private static let logoutURL = URL(string: "https://claude.ai/logout")!

    let store = WKWebsiteDataStore.nonPersistent()

    private var webView: WKWebView?
    private var anchorReady = false
    private var pending: CheckedContinuation<Void, Error>?
    private var savedFingerprint: String?

    /// Für das Anmeldefenster dieselbe Konfiguration - es teilt den Cookie-Speicher,
    /// die Anmeldung dort gilt also sofort auch hier.
    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // Wie Safari selbst: ohne den Zusatz hält claude.ai die WebView für einen
        // veralteten Browser.
        let os = ProcessInfo.processInfo.operatingSystemVersion
        configuration.applicationNameForUserAgent = "Version/\(os.majorVersion).\(os.minorVersion) Safari/605.1.15"
        return configuration
    }

    // MARK: - Sitzung

    func restore(_ cookies: [SessionKeychain.StoredCookie]) async {
        let now = Date()
        for stored in cookies {
            guard let cookie = stored.cookie, (cookie.expiresDate ?? .distantFuture) > now else { continue }
            await store.httpCookieStore.setCookie(cookie)
        }
        savedFingerprint = Self.fingerprint(cookies)
        anchorReady = false
    }

    func hasSession() async -> Bool {
        await claudeCookies().contains(where: Self.isSessionCookie)
    }

    /// Die zuletzt in claude.ai benutzte Organisation (Cookie `lastActiveOrg`).
    func lastActiveOrganization() async -> String? {
        await claudeCookies().first(where: { $0.name == "lastActiveOrg" })?.value
    }

    /// Legt die Cookies in den Schlüsselbund, wenn sich an der Sitzung etwas
    /// geändert hat (claude.ai und Cloudflare erneuern sie von Zeit zu Zeit).
    func persistIfChanged() async {
        let cookies = await claudeCookies().map(SessionKeychain.StoredCookie.init)
        guard cookies.contains(where: { Self.isSessionName($0.name) }) else { return }
        let fingerprint = Self.fingerprint(cookies)
        guard fingerprint != savedFingerprint else { return }
        if await Task.detached(operation: { SessionKeychain.save(cookies) }).value {
            savedFingerprint = fingerprint
        }
    }

    /// Meldet bei claude.ai ab (die Sitzung endet dort, nicht nur hier) und
    /// vergisst dann alles hier.
    func signOut() async {
        if await hasSession() {
            let webView = ensureWebView()
            // `/logout` ist eine Seite der Web-App: deren Skript beendet die
            // Sitzung und leitet auf `/login` weiter. Höchstens 10 s warten.
            webView.load(URLRequest(url: Self.logoutURL))
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                if webView.url?.path.hasPrefix("/login") == true { break }
            }
        }
        await forget()
    }

    /// Vergisst die Sitzung nur hier: Cookies im Speicher und den
    /// Schlüsselbund-Eintrag. Für eine Sitzung, die claude.ai ohnehin nicht mehr kennt.
    func forget() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await Task.detached { SessionKeychain.delete() }.value
        savedFingerprint = nil
        anchorReady = false
        webView?.loadHTMLString("", baseURL: nil)
    }

    // MARK: - Abfragen

    /// `GET` gegen claude.ai, mit der Sitzung. Liefert den Rumpf bei 2xx.
    func get(_ path: String) async throws -> Data {
        try await ensureAnchor()
        var response = try await fetch(path)
        if response.isChallenge {
            // Cloudflare hat die Seite für ungültig erklärt - neu laden, damit die
            // Prüfung im Hintergrund läuft, und einmal wiederholen.
            anchorReady = false
            try await ensureAnchor()
            response = try await fetch(path)
        }
        if response.isChallenge { throw Failure.challenged }
        switch response.status {
        case 200..<300:
            return Data(response.body.utf8)
        case 401, 403:
            throw Failure.signedOut
        default:
            throw Failure.http(response.status)
        }
    }

    private struct Response {
        var status: Int
        var body: String
        var contentType: String

        /// Cloudflare antwortet mit einer HTML-Seite statt JSON.
        var isChallenge: Bool {
            (status == 403 || status == 503 || status == 429) && contentType.contains("text/html")
        }
    }

    private func fetch(_ path: String) async throws -> Response {
        let webView = ensureWebView()
        let script = """
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), 20000);
            try {
              const response = await fetch(path, {
                credentials: 'include',
                headers: {'accept': 'application/json'},
                signal: controller.signal
              });
              return [response.status, await response.text(), response.headers.get('content-type') || ''];
            } finally {
              clearTimeout(timer);
            }
            """
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(
                script, arguments: ["path": path], in: nil, contentWorld: .defaultClient)
        } catch {
            anchorReady = false
            throw Failure.unreachable(error.localizedDescription)
        }
        guard let parts = value as? [Any], parts.count == 3,
              let status = (parts[0] as? NSNumber)?.intValue,
              let body = parts[1] as? String,
              let contentType = parts[2] as? String
        else { throw Failure.unreachable("Unerwartete Antwort") }
        return Response(status: status, body: body, contentType: contentType)
    }

    private func ensureAnchor() async throws {
        if anchorReady, ensureWebView().url?.host == Self.base.host { return }
        let webView = ensureWebView()
        try await load(Self.anchorURL, in: webView)
        // Eine Cloudflare-Prüfung kommt als HTML-Seite und leitet nach dem Lösen
        // weiter - bis zu 15 s auf das JSON warten.
        for _ in 0..<15 {
            let type = try? await webView.evaluateJavaScript("document.contentType") as? String
            if type?.contains("json") == true {
                anchorReady = true
                return
            }
            // Ohne Sitzung antwortet claude.ai 401 mit JSON - auch das taugt als
            // Anker, `get` meldet dann `signedOut`. Bleibt es HTML, ist es eine Prüfung.
            try? await Task.sleep(for: .seconds(1))
        }
        throw Failure.challenged
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending?.resume(throwing: CancellationError())
            pending = continuation
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: makeConfiguration())
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pending?.resume()
        pending = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        anchorReady = false
        finish(with: Failure.unreachable("WebKit beendet"))
    }

    private func finish(with error: Error) {
        // Eine abgebrochene Navigation (-999) heißt nur: eine neue hat sie ersetzt,
        // etwa die Weiterleitung nach einer Cloudflare-Prüfung.
        if (error as NSError).code == NSURLErrorCancelled { return }
        pending?.resume(throwing: Failure.unreachable(error.localizedDescription))
        pending = nil
    }

    // MARK: - Cookies

    private func claudeCookies() async -> [HTTPCookie] {
        await store.httpCookieStore.allCookies().filter { $0.domain.hasSuffix("claude.ai") }
    }

    /// Der eigentliche Sitzungs-Cookie heißt `sessionKey` (bzw. eine neuere
    /// Fassung davon); `…LC` daneben sind lesbare Begleiter ohne Geheimnis.
    static func isSessionName(_ name: String) -> Bool {
        name.hasPrefix("sessionKey") && !name.hasSuffix("LC")
    }

    private static func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        isSessionName(cookie.name)
    }

    /// Was zählt, um zu entscheiden, ob neu gespeichert werden muss - nicht die
    /// Statistik-Cookies, die sich bei jedem Aufruf ändern.
    static func fingerprint(_ cookies: [SessionKeychain.StoredCookie]) -> String {
        cookies
            .filter { isSessionName($0.name) || $0.name.hasPrefix("cf_") || $0.name == "lastActiveOrg" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value);\($0.expires?.timeIntervalSince1970 ?? 0)" }
            .joined(separator: "|")
    }
}
