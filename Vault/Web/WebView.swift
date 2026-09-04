import SwiftUI
import WebKit

/// Bettet eine der drei Weboberflaechen ein.
///
/// Wichtig ist der `default()`-Datenspeicher: er ist persistent, also
/// ueberleben die Zugangs-Cookies (und der Login des Finance Cockpits) einen
/// App-Neustart. Ein `nonPersistent()`-Speicher wuerde bei jedem Start eine
/// neue Anmeldung verlangen.
struct WebView: UIViewRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        // Ziehen zum Aktualisieren: die drei Seiten laden ihre Daten beim
        // Oeffnen und haben selbst keinen Aktualisieren-Knopf.
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.refresh(_:)),
                          for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        context.coordinator.webView = webView

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        weak var webView: WKWebView?

        @objc func refresh(_ sender: UIRefreshControl) {
            webView?.reload()
            sender.endRefreshing()
        }
    }
}
