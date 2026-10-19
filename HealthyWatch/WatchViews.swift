import SwiftUI

/// Ohne Training: der Tagesstand wie auf der Komplikation.
struct WatchHomeView: View {

    @State private var snapshot = ComplicationStore.snapshot()

    var body: some View {
        VStack(spacing: 8) {
            KcalGaugeView(consumed: isToday ? snapshot?.consumedKcal : nil, target: snapshot?.targetKcal)
                .scaleEffect(1.6)
                .frame(height: 100)
            Text("Healthy").font(.footnote).foregroundStyle(.secondary)
        }
        .task {
            #if DEBUG
            if ["workout", "machine"].contains(ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"]) {
                WorkoutManager.shared.showDemo()
                return
            }
            if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "kcal" {
                snapshot = ComplicationSnapshot(date: Self.todayISO, consumedKcal: 1550, targetKcal: 2300,
                                                fetchedAt: Date())
                return
            }
            #endif
            await WorkoutManager.shared.requestAuthorization()
            snapshot = ComplicationStore.snapshot()
        }
    }

    private var isToday: Bool { snapshot?.date == Self.todayISO }

    private static var todayISO: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
}

/// Das laufende Training: oben die Werte, darunter das Geraet mit „Satz
/// erledigt“, ganz unten „Beenden“ - als Seiten zum Drehen der Krone.
///
/// Hat die Uebung eine Spanne (Felix, 19.10.), dreht die Krone auf der Seite
/// des Geraets die Wiederholungen statt der Seiten - weiter geht es dort mit
/// Wischen.
struct WatchWorkoutView: View {

    private enum Page { case metrics, machine, finish }

    private var workout: WorkoutManager { WorkoutManager.shared }

    @State private var page = WatchWorkoutView.firstPage
    /// Was „Satz erledigt“ mitschickt, nur mit Spanne: vorbelegt mit der oberen
    /// Grenze, bei jedem neuen Satz wieder. `Double`, weil die Krone so dreht.
    @State private var reps = 0.0
    @FocusState private var repsFocused: Bool

    var body: some View {
        TabView(selection: $page) {
            metrics.tag(Page.metrics)
            machine.tag(Page.machine)
            finish.tag(Page.finish)
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: setKey, initial: true) {
            reps = Double(workout.current?.reps ?? 0)
            focusReps()
        }
        .onChange(of: page) { focusReps() }
    }

    /// Ein neuer Satz, ein anderes Geraet oder ein anderes Ziel.
    private var setKey: String {
        workout.current.map { "\($0.exerciseId)/\($0.set)/\($0.reps)" } ?? ""
    }

    private var range: ClosedRange<Int>? {
        workout.current.flatMap { GymExercise.range(reps: $0.reps, repsMin: $0.repsMin) }
    }

    /// Die Krone gehoert den Wiederholungen, solange das Geraet zu sehen ist und
    /// eine Spanne hat - sonst blaettert sie wie bisher.
    private func focusReps() {
        repsFocused = page == .machine && range != nil
    }

    private static var firstPage: Page {
        #if DEBUG
        // Fuer Aufnahmen: der Uhren-Simulator kann nicht blaettern.
        if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "machine" { return .machine }
        #endif
        return .metrics
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.duration(since: workout.startDate ?? context.date, now: context.date))
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

    @ViewBuilder
    private var machine: some View {
        if let current = workout.current {
            VStack(spacing: 6) {
                Text(current.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let note = current.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Text("Satz \(current.set) von \(current.sets)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                        Text(GymFormat.range(range))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("× " + GymFormat.weight(current.weightKg))
                    }
                    .font(.title3.monospacedDigit().weight(.semibold))
                } else {
                    Text("\(current.reps) × " + GymFormat.weight(current.weightKg))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                Button {
                    workout.setDone(reps: range == nil ? nil : Int(reps.rounded()))
                } label: {
                    Label("Satz erledigt", systemImage: "checkmark")
                }
                .tint(.green)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: workout.everythingDone ? "checkmark.circle.fill" : "iphone")
                    .font(.largeTitle)
                    .foregroundStyle(workout.everythingDone ? .green : .secondary)
            }
        }
    }

    private var finish: some View {
        Button(role: .destructive) {
            Task { await workout.end() }
        } label: {
            Label("Beenden", systemImage: "xmark")
        }
    }

    static func duration(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
