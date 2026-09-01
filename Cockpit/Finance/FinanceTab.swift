import SwiftUI

/// Das Finance Cockpit - dauerhaft eine WebView, nicht als Zwischenstand.
///
/// Es hat kein JSON-API und soll keins bekommen: die Seite wird taeglich von
/// einem Claude-Lauf neu gestaltet, eine feste Datenstruktur wuerde genau das
/// verhindern (siehe docs/ENTSCHEIDUNGEN.md). Angemeldet wird sich hier im
/// WebView mit Passwort und Einmalcode; das Session-Cookie haelt sieben Tage
/// und verlaengert sich bei Nutzung.
struct FinanceTab: View {
    var body: some View {
        WebView(url: Backend.finance.url)
            .ignoresSafeArea(edges: .bottom)
    }
}
