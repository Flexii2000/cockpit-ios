import SwiftUI

/// Sport (Felix, 23.10.): Padel - die Autobuchung bei Playtomic - und das Gym, das bis dahin in
/// Healthy lag. Dazu eine eigene Uhr-App fuer Krafttraining und Padel-Matches.
@main
struct SportApp: App {

    @State private var access = Access()
    /// Fuer den Start im Hintergrund: siehe AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste Anfrage rausgeht - Padel und der Weight
                // Tracker kennen nur Cookies.
                .task {
                    await access.applyCookies()
                    // Erst mit Cookies: sonst kaeme jedes Nachsenden als „kein Zugang“ zurueck.
                    PendingSync.start()
                    await PadelReportOutbox.shared.deliver(cookie: nil)
                }
        }
    }
}
