import SwiftUI
import WebKit

/// Das Anmeldefenster: die echte Anmeldeseite von claude.ai in einer WebView.
/// Felix meldet sich dort an wie im Browser (E-Mail und Code); die App sieht
/// dabei weder Passwort noch Code, nur am Ende die Cookies der Sitzung - und die
/// gehen in den Schlüsselbund (`SessionKeychain`), nirgends sonst hin.
///
/// Dasselbe Fenster zeigt eine Cloudflare-Prüfung, wenn die unsichtbare WebView
/// an einer hängen bleibt.
struct LoginView: View {

    static let windowID = "login"

    let model: UsageModel

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        LoginWebView(model: model)
            .frame(minWidth: 420, minHeight: 560)
            .onChange(of: model.loginCompletedAt) {
                dismissWindow(id: Self.windowID)
            }
    }
}

private struct LoginWebView: NSViewRepresentable {

    let model: UsageModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        // Dieselbe Konfiguration wie die unsichtbare WebView: derselbe
        // Cookie-Speicher, also gilt die Anmeldung sofort.
        let webView = WKWebView(frame: .zero, configuration: model.web.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        Task { @MainActor in
            let url = await model.prepareLogin()
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {

        private let model: UsageModel
        private var check: Task<Void, Never>?
        private var cookieStore: WKHTTPCookieStore?

        init(model: UsageModel) {
            self.model = model
        }

        func attach(to webView: WKWebView) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.add(self)
            cookieStore = store
        }

        func detach() {
            check?.cancel()
            cookieStore?.remove(self)
            cookieStore = nil
        }

        // claude.ai wechselt nach der Anmeldung die Seite per Skript, ohne neue
        // Navigation - darum zählt auch jede Cookie-Änderung als Anlass zu prüfen.
        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in self.scheduleCheck() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scheduleCheck()
        }

        /// Fenster, die die Seite öffnen will (etwa „Weiter mit Google“), im selben
        /// Fenster laden statt sie zu verlieren.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Eine Sekunde Ruhe abwarten: beim Anmelden setzt claude.ai mehrere
        /// Cookies kurz hintereinander. Nimmt claude.ai die Sitzung noch nicht,
        /// bis zu 30 s lang alle 3 s nachfragen - ein weiteres Signal muss nicht kommen.
        private func scheduleCheck() {
            check?.cancel()
            check = Task { [model] in
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<10 {
                    guard !Task.isCancelled else { return }
                    if await model.loginMayHaveCompleted() != .notYet { return }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }
}
