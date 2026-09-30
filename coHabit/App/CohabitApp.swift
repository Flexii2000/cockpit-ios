import SwiftUI

/// Habits gemeinsam mit Freunden (Vertrag: ../habits/docs/COHABIT-CONTRACT.md).
@main
struct CohabitApp: App {

    /// Push-Kennung und der Tipp auf eine Meldung.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    // cohabit://… aus Kachel, Meldung oder einer anderen App.
                    Router.shared.open(url)
                }
        }
    }
}
