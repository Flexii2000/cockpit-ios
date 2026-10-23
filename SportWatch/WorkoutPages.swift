import SwiftUI
import WatchKit

// Seiten, die Krafttraining und Padel teilen - wie im Trainings-Programm der Uhr: links die
// Steuerung, rechts die Musik.

/// Beenden - mit Rueckfrage, beim Padel geht danach das Ergebnis raus. Beim Padel dazu
/// „Zurueck“ fuer einen versehentlich gezaehlten Punkt.
struct WorkoutControlsPage: View {

    var undo: (() -> Void)?

    @State private var confirming = false
    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label("Beenden", systemImage: "xmark")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .tint(.red)
            if let undo {
                Button(action: undo) {
                    Label("Zurück", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .disabled(workout.padel?.history.isEmpty ?? true)
            }
        }
        .confirmationDialog("Training beenden?", isPresented: $confirming) {
            Button("Beenden", role: .destructive) {
                Task { await workout.end() }
            }
        }
    }
}

/// Dauer, Puls und kcal - gross, zum Ablesen im Spiel.
struct WorkoutMetricsPage: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(WorkoutFormat.duration(since: workout.startDate ?? context.date, now: context.date))
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            Label(workout.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "– bpm", systemImage: "heart.fill")
                .foregroundStyle(.red)
            Label(workout.activeKcal.map { "\(Int($0.rounded())) kcal" } ?? "– kcal", systemImage: "flame.fill")
                .foregroundStyle(.orange)
        }
        .font(.title3.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Die kleine Zeile oben auf der Trainingsseite: Dauer, Puls, kcal.
struct WorkoutMetricsLine: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(WorkoutFormat.duration(since: workout.startDate ?? context.date, now: context.date))
                    .foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            Label(workout.heartRate.map { "\(Int($0.rounded()))" } ?? "–", systemImage: "heart.fill")
                .foregroundStyle(.red)
            Label(workout.activeKcal.map { "\(Int($0.rounded()))" } ?? "–", systemImage: "flame.fill")
                .foregroundStyle(.orange)
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption2.monospacedDigit().weight(.semibold))
    }
}

/// Symbol und Zahl dicht beieinander - die Zeile ist schmal.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

enum WorkoutFormat {
    /// „12:07“, ab einer Stunde „1:02:07“.
    static func duration(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
