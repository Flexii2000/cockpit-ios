import HealthKit
import SwiftUI
import WatchKit

/// Healthy auf der Uhr (14.10.): die kcal-Komplikation und das Krafttraining
/// aus dem Gym-Tab. Die App selbst zeigt nur das Noetigste - das Training, wenn
/// eines laeuft, sonst den Tagesstand.
@main
struct HealthyWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        // Das iPhone schickt Token und Stand auch, wenn die App nicht laeuft -
        // dann weckt watchOS sie kurz hierfuer.
        .backgroundTask(.watchConnectivity) {
            await WatchSession.shared.waitForPendingContent()
        }
    }
}

/// Startet das iPhone ein Training (`startWatchApp`), kommt es hier an - auch
/// wenn die App gar nicht lief.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        WatchSession.shared.activate()
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutManager.shared.start(with: workoutConfiguration)
        }
    }
}

struct WatchRootView: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        if workout.isRunning {
            WatchWorkoutView()
        } else {
            WatchHomeView()
        }
    }
}
