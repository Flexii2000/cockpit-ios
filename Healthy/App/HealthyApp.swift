import SwiftUI

/// Essen und Gewicht - das, was man taeglich eintraegt.
@main
struct HealthyApp: App {

    @State private var access = Access()
    /// Fuer den Start im Hintergrund: siehe AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste Anfrage rausgeht - sonst schickt
                // nginx den Kalorienzaehler auf die Startseite um.
                .task {
                    await access.applyCookies()
                    // Die Kennung kann sich geaendert haben - deshalb bei
                    // jedem Start neu melden, aber ohne Nachfrage.
                    await Notifications.registerForPushIfAllowed()
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["COCKPIT_ASK_PUSH"] == "1" {
                        await Notifications.requestPermission()
                    }
                    #endif
                }
        }
    }
}
