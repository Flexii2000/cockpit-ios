import SwiftUI

/// Healthy auf der Uhr (14.10.): die kcal-Komplikation. Die App selbst zeigt den Tagesstand.
/// Das Krafttraining ist am 23.10. mit dem Gym-Tab nach Sport gezogen, samt eigener Uhr-App.
@main
struct HealthyWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
        // Das iPhone schickt Token und Stand auch, wenn die App nicht laeuft -
        // dann weckt watchOS sie kurz hierfuer.
        .backgroundTask(.watchConnectivity) {
            await WatchSession.shared.waitForPendingContent()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        WatchSession.shared.activate()
    }
}
