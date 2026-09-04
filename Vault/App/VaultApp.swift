import SwiftUI

/// Noten und Finanzen - das, was man nachliest und das niemand mitlesen soll.
/// Die ganze App steht hinter Face ID.
@main
struct VaultApp: App {

    @State private var access = Access()
    @State private var lock = BiometricLock(reason: "Damit Noten und Finanzen nicht offen daliegen.")
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(lock: lock)
                .environment(access)
                .task {
                    await access.applyCookies()
                    // Die Kennung geht an den Notendienst, sobald dort eine
                    // Sitzung steht (GradesStore) - hier nur bei Apple melden.
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
