import SwiftUI
import WidgetKit

/// Essen und Gewicht - das, was man taeglich eintraegt.
@main
struct HealthyApp: App {

    /// Als einzige App mit dem persoenlichen Token (seit 10.11.): Healthy laeuft
    /// auch auf einem zweiten iPhone, mit dem Zugang genau einer Person.
    @State private var access = Access(usesHealthToken: true)
    /// Fuer den Start im Hintergrund: siehe AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste Anfrage rausgeht - sonst schickt
                // nginx den Kalorienzaehler auf die Startseite um.
                .task {
                    access.onHealthAccessChanged = Self.healthAccessChanged
                    await access.applyCookies()
                    // Erst mit Cookies: sonst kaeme jedes Nachsenden als „kein Zugang“ zurueck.
                    PendingSync.start()
                    // Wartende Eintraege zaehlen auch auf der Kalorien-Kachel vorlaeufig mit.
                    FoodWidgetBridge.start()
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

    /// Der persoenliche Token wurde gesetzt, gewechselt oder entfernt: alles,
    /// was ausserhalb der Tabs am Zugang haengt, zieht nach. Die Tabs selbst
    /// baut `RootView` neu (`healthGeneration`).
    @MainActor
    private static func healthAccessChanged() {
        // Anker und Cursor des Health-Abgleichs gelten je Person.
        HealthSync.shared.accessChanged()
        // Kacheln und Uhr holen den Tag selbst - mit dem Cookie, der jetzt gilt.
        WidgetCenter.shared.reloadAllTimelines()
        WatchLink.shared.sendContext()
        // Die Push-Kennung gehoert jetzt zu dieser Person: neu melden.
        Task { await Notifications.registerForPushIfAllowed() }
    }
}
