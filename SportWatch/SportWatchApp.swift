import HealthKit
import SwiftUI
import WatchKit

/// Sport auf der Uhr (23.10.): das Krafttraining aus dem Gym-Tab (bis dahin in der Uhr-App von
/// Healthy) und Padel-Matches, die hier starten - beide als Training in Health.
@main
struct SportWatchApp: App {

    @WKApplicationDelegateAdaptor(SportWatchDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            SportWatchRootView()
        }
        // Das iPhone schickt Token und Botschaften auch, wenn die App nicht laeuft -
        // dann weckt watchOS sie kurz hierfuer.
        .backgroundTask(.watchConnectivity) {
            await WatchSession.shared.waitForPendingContent()
        }
    }
}

final class SportWatchDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        WatchSession.shared.activate()
    }

    /// Startet das iPhone ein Krafttraining (`startWatchApp`), kommt es hier an - auch wenn die
    /// App gar nicht lief.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutManager.shared.startGym(with: workoutConfiguration)
        }
    }

    /// Nach einem Absturz mitten im Training.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            await WorkoutManager.shared.recover()
        }
    }
}

struct SportWatchRootView: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        switch workout.kind {
        case .gym:   GymWatchView()
        case .padel: PadelWatchView()
        case nil:    SportHomeView()
        }
    }
}

/// Ohne Training: Padel starten. Das Krafttraining startet am iPhone im Gym-Tab.
struct SportHomeView: View {

    /// Golden oder Silver Point - gemerkt fuer das naechste Match.
    @AppStorage("padel.rule") private var rule = PadelDeuceRule.golden
    /// Wer zuerst aufschlaegt - jedes Match neu, vorbelegt mit „Wir“.
    @State private var firstServer = PadelSide.us
    @State private var starting = false

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button {
                    starting = true
                    Task {
                        await workout.startPadel(rule: rule, firstServer: firstServer)
                        starting = false
                    }
                } label: {
                    Label("Padel", systemImage: "figure.tennis")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(starting)
                HStack(spacing: 6) {
                    choice(rule == .golden ? "Golden" : "Silver", symbol: "star.circle") {
                        rule = rule == .golden ? .silver : .golden
                    }
                    choice(firstServer == .us ? "Wir" : "Die", symbol: "tennisball") {
                        firstServer = firstServer.other
                    }
                }
                if let last = workout.lastReport, Calendar.current.isDateInToday(last.endedAt), !last.sets.isEmpty {
                    Text(last.summary)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sport")
        .task {
            #if DEBUG
            if let demo = ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] {
                workout.showDemo(demo)
                return
            }
            #endif
            await workout.requestAuthorization()
            await PadelReportOutbox.shared.deliver(cookie: WatchSession.shared.cookie)
        }
    }

    /// Ein Knopf, der zwischen zwei Werten wechselt - eine Auswahlliste waere auf der Uhr zu
    /// umstaendlich fuer zwei Moeglichkeiten.
    private func choice(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }
}
