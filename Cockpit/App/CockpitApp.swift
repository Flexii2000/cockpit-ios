import SwiftUI

@main
struct CockpitApp: App {

    @State private var access = Access()
    /// Zwei Sperren, nicht eine: wer die Finanzen aufgemacht hat, hat damit
    /// nicht auch die Noten offen. Der Text sagt jeweils, worum es geht.
    @State private var financeLock = BiometricLock(
        reason: "Damit deine Finanzen nicht offen daliegen.")
    @State private var gradesLock = BiometricLock(
        reason: "Damit deine Noten nicht offen daliegen.")
    /// Fuer den Start im Hintergrund: siehe AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(financeLock: financeLock, gradesLock: gradesLock)
                .environment(access)
                // Muss laufen, bevor die erste WebView laedt - sonst schickt
                // nginx den Kalorienzaehler-Tab auf die Startseite um.
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
