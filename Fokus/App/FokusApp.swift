import SwiftUI

/// To-Do und der Wald. Die Habits sind nach coHabit umgezogen.
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
