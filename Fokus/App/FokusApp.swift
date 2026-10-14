import SwiftUI

/// To-Do, der Wald, die Einkaufsliste und die Evaluation. Die Habits sind nach
/// coHabit umgezogen, Einkauf und Evaluation kamen am 14.10. aus Healthy.
@main
struct FokusApp: App {

    @State private var access = Access()
    /// Fuer die Erinnerungen des To-Do-Dienstes: Push-Kennung und Weiche.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                .task {
                    await access.applyCookies()
                    // Erst mit Cookies: sonst kaeme jedes Nachsenden als „kein Zugang“ zurueck.
                    PendingSync.start()
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
