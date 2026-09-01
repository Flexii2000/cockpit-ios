import SwiftUI

@main
struct CockpitApp: App {

    @State private var access = Access()
    /// Fuer den Start im Hintergrund: siehe AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste WebView laedt - sonst schickt
                // nginx den Kalorienzaehler-Tab auf die Startseite um.
                .task {
                    await access.applyCookies()
                    // Die Kennung kann sich geaendert haben - deshalb bei
                    // jedem Start neu melden, aber ohne Nachfrage.
                    await Notifications.registerForPushIfAllowed()
                }
        }
    }
}
