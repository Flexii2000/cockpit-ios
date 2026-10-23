import SwiftUI
import WatchKit

/// Das Krafttraining auf der Uhr (14.10., neu gestaltet 23.10.): eine Seite mit allem, was man
/// am Geraet braucht - oben Dauer, Puls und kcal, darunter das Geraet, die Saetze als Punkte,
/// Wiederholungen × Gewicht, die Pause seit dem letzten Satz und gross „Satz erledigt“. Links
/// die Steuerung, rechts alle Geraete zum Wechseln und die Musik.
///
/// Geblaettert wird quer - so bleibt die Krone frei fuer die Wiederholungen, wenn die Uebung
/// eine Spanne hat (19.10.).
struct GymWatchView: View {

    enum Page: Hashable { case controls, training, stations, music }

    @State private var page = GymWatchView.firstPage

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsPage().tag(Page.controls)
            GymTrainingPage().tag(Page.training)
            GymStationsPage { page = .training }.tag(Page.stations)
            NowPlayingView().tag(Page.music)
        }
        .tabViewStyle(.page)
    }

    private static var firstPage: Page {
        #if DEBUG
        // Fuer Aufnahmen: der Uhren-Simulator kann nicht blaettern.
        if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "stations" { return .stations }
        #endif
        return .training
    }
}

/// Das Geraet, das dran ist.
struct GymTrainingPage: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    /// Was „Satz erledigt“ mitschickt, nur mit Spanne: vorbelegt mit der oberen Grenze, bei
    /// jedem neuen Satz wieder. `Double`, weil die Krone so dreht.
    @State private var reps = 0.0
    @FocusState private var repsFocused: Bool

    var body: some View {
        VStack(spacing: 3) {
            WorkoutMetricsLine()
            if let current = workout.plan?.current {
                machine(current)
            } else {
                done
            }
        }
        .onChange(of: setKey, initial: true) {
            reps = Double(workout.plan?.current?.reps ?? 0)
            repsFocused = range != nil
        }
    }

    /// Ein neuer Satz, ein anderes Geraet oder ein anderes Ziel.
    private var setKey: String {
        workout.plan?.current.map { "\($0.exerciseId)/\($0.set)/\($0.reps)" } ?? ""
    }

    private var range: ClosedRange<Int>? {
        workout.plan?.current.flatMap { GymExercise.range(reps: $0.reps, repsMin: $0.repsMin) }
    }

    private func machine(_ current: WorkoutCurrent) -> some View {
        VStack(spacing: 3) {
            Text(current.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
            if let note = current.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            SetDots(done: current.set - 1, total: current.sets)
            repsAndWeight(current)
            PauseLine(since: workout.lastSetAt)
            Button {
                workout.setDone(reps: range == nil ? nil : Int(reps.rounded()))
            } label: {
                Label("Satz erledigt", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    @ViewBuilder
    private func repsAndWeight(_ current: WorkoutCurrent) -> some View {
        if let range {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(reps.rounded()))")
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    // Dass die Krone hier dreht - einen Rahmen zeichnet watchOS dafuer nicht.
                    .overlay {
                        if repsFocused {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.green, lineWidth: 1.5)
                        }
                    }
                    .focusable()
                    .focused($repsFocused)
                    .digitalCrownRotation($reps, from: 1, through: 100, by: 1, sensitivity: .low,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel("Wiederholungen")
                Text("× " + GymFormat.weight(current.weightKg))
                Text(GymFormat.range(range))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.title3.monospacedDigit().weight(.semibold))
        } else {
            Text("\(current.reps) × " + GymFormat.weight(current.weightKg))
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    private var done: some View {
        VStack(spacing: 6) {
            let finished = !(workout.plan?.stations.isEmpty ?? true)
            Image(systemName: finished ? "checkmark.circle.fill" : "iphone")
                .font(.largeTitle)
                .foregroundStyle(finished ? .green : .secondary)
            if finished {
                Text("Alles erledigt").font(.footnote)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Die Saetze des Geraets als Punkte: erledigt gefuellt, der naechste mit Rand.
private struct SetDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < done ? Color.green : Color.clear)
                    .overlay(Circle().strokeBorder(index == done ? Color.green : Color.secondary,
                                                   lineWidth: index < done ? 0 : 1.5))
                    .frame(width: 9, height: 9)
            }
            Text("\(min(done + 1, total))/\(total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Satz \(min(done + 1, total)) von \(total)")
    }
}

/// „Pause 1:12“ seit dem letzten Satz - ab 90 Sekunden gruen (Felix, 23.10.); die Uhr
/// vibriert dann einmal (`WorkoutManager`).
private struct PauseLine: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let since, context.date.timeIntervalSince(since) < 30 * 60 {
                let elapsed = context.date.timeIntervalSince(since)
                Label("Pause " + WorkoutFormat.duration(since: since, now: context.date), systemImage: "timer")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(elapsed >= WorkoutManager.pauseAlertAfter ? Color.green : Color.secondary)
            }
        }
    }
}

/// Alle Geraete des Tages - antippen macht eines zum aktuellen, etwa wenn das naechste besetzt
/// ist (Felix, 23.10.).
struct GymStationsPage: View {

    let onChosen: () -> Void

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        List(workout.plan?.stations ?? []) { station in
            let isCurrent = station.exerciseId == workout.plan?.current?.exerciseId
            Button {
                workout.choose(station.exerciseId)
                onChosen()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: station.isDone ? "checkmark.circle.fill"
                          : isCurrent ? "circle.inset.filled" : "circle")
                        .foregroundStyle(station.isDone || isCurrent ? Color.green : Color.secondary)
                    Text(station.name)
                        .lineLimit(2)
                        .foregroundStyle(station.isDone ? .secondary : .primary)
                    Spacer(minLength: 2)
                    Text("\(station.done)/\(station.sets)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(station.isDone)
        }
    }
}
