import SwiftUI

/// Das Finance Cockpit - dauerhaft eine WebView, nicht als Zwischenstand.
///
/// Es hat kein JSON-API und soll keins bekommen: die Seite wird taeglich von
/// einem Claude-Lauf neu gestaltet, eine feste Datenstruktur wuerde genau das
/// verhindern (siehe docs/ENTSCHEIDUNGEN.md). Angemeldet wird sich hier im
/// WebView mit Passwort und Einmalcode; das Session-Cookie haelt sieben Tage
/// und verlaengert sich bei Nutzung.
struct FinanceTab: View {

    let lock: FinanceLock

    var body: some View {
        ZStack {
            if lock.isUnlocked {
                WebView(url: Backend.finance.url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                lockScreen
            }
        }
        // Beim Wechsel auf den Tab gleich fragen - ein zusaetzlicher Tipp auf
        // "Entsperren" waere ein Klick, der nichts entscheidet.
        .task { await lock.unlock() }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Finanzen sind gesperrt")
                .font(.headline)
            if let failure = lock.lastFailure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Entsperren") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
