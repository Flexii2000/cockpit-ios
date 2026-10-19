import SwiftUI

/// Das laufende Training (Felix, 14.10.): oben die Werte der Uhr, darunter
/// gross das Geraet, das dran ist, unten die uebrigen - ein Tipp macht eines
/// davon zum aktuellen. Ohne Uhr steht oben nur die Dauer.
struct GymWorkoutView: View {

    let store: GymStore
    let day: GymDay
    @Binding var sheet: GymSheet?

    /// Die Wiederholungen des Satzes, der als naechster abgehakt wird - nur bei
    /// einer Spanne, und nur fuer diesen Satz, nicht fuer den Plan (Felix,
    /// 19.10.). `nil` ist die obere Grenze; nach jedem Haken und beim
    /// Geraetewechsel steht sie wieder da (`progress`).
    @State private var nextSetReps: Int?

    private var mirror: WorkoutMirror { WorkoutMirror.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                metrics
                if let exercise = store.currentExercise {
                    current(exercise)
                } else {
                    allDone
                }
                others
                Button(role: .destructive) {
                    store.finish()
                    mirror.finish()
                } label: {
                    Text("Training beenden")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("gymFinish")
            }
            .padding(16)
            .padding(.bottom, 60)
        }
        // Was die Uhr gerade zeigen soll - bei jedem Wechsel neu.
        .onChange(of: watchState, initial: true) { _, state in mirror.send(current: state) }
        .onChange(of: progress) { nextSetReps = nil }
        .onAppear {
            mirror.onSetDone = { exerciseId, reps in
                // Der Tag von jetzt, nicht der vom Erscheinen der Ansicht - sonst
                // haekte die Uhr mit einem Gewicht von vorhin ab.
                guard let day = store.workoutDay,
                      let exercise = day.exercises.first(where: { $0.id == exerciseId }) else { return }
                store.tickNext(exercise, on: day, reps: reps)
            }
            mirror.onEnd = { store.finish() }
        }
    }

    /// Welcher Satz an welchem Geraet dran ist - aendert es sich, gilt fuer den
    /// naechsten wieder die obere Grenze.
    private var progress: String {
        guard let exercise = store.currentExercise else { return "" }
        return "\(exercise.id)/\(store.doneCount(exercise, on: day))"
    }

    /// Mit Spanne die Wiederholungen fuer den naechsten Haken, sonst `nil`
    /// (dann hakt der Plan ab).
    private func repsForNextSet(_ exercise: GymExercise) -> Int? {
        exercise.repsRange == nil ? nil : nextSetReps ?? exercise.reps
    }

    // MARK: - Werte

    private var metrics: some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                metric(value: Self.duration(since: store.workout?.startedAt ?? context.date, now: context.date),
                       unit: "Dauer", symbol: "timer", tint: .primary)
            }
            if let live = mirror.metrics {
                metric(value: live.heartRate.map { String(Int($0.rounded())) } ?? "–",
                       unit: "bpm", symbol: "heart.fill", tint: .red)
                metric(value: live.activeKcal.map { String(Int($0.rounded())) } ?? "–",
                       unit: "kcal", symbol: "flame.fill", tint: .orange)
            }
        }
        .dashboardCard()
        // Als Container - sonst traegt jeder Knopf darin diese Kennung statt seiner eigenen.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gymMetrics")
    }

    private func metric(value: String, unit: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// „12:07“, ab einer Stunde „1:02:07“.
    static func duration(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Das aktuelle Geraet

    private func current(_ exercise: GymExercise) -> some View {
        let done = store.doneCount(exercise, on: day)
        let reps = repsForNextSet(exercise)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.machineName(exercise.machineId))
                        .font(.title2.weight(.bold))
                    Spacer()
                    Text("Satz \(min(done + 1, exercise.sets)) von \(exercise.sets)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // Ein Feld, nicht nur im Blatt: die Sitzeinstellung traegt Felix am Geraet ein.
                GymNoteField(note: store.state?.machine(exercise.machineId)?.note) {
                    store.setNote(machineId: exercise.machineId, to: $0)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
                .id(exercise.id)
            }
            GymSetCircles(store: store, day: day, exercise: exercise, size: 40, reps: reps)
            GymPlanControls(store: store, dayId: day.id, exercise: exercise,
                            nextSetReps: Binding { nextSetReps ?? exercise.reps } set: { nextSetReps = $0 })
                // Ein anderes Geraet ist ein anderes Feld - sonst stuende im
                // Gewicht kurz noch die Zahl des vorigen.
                .id(exercise.id)
            if let last = store.state?.last[exercise.machineId] {
                Button {
                    sheet = .history(machineId: exercise.machineId)
                } label: {
                    Text(GymFormat.last(last))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                store.tickNext(exercise, on: day, reps: reps)
            } label: {
                Label("Satz erledigt", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("gymSetDone")
        }
        .dashboardCard()
        // Als Container - sonst traegt jeder Knopf darin diese Kennung statt seiner eigenen.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gymCurrent")
    }

    private var allDone: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text(day.name).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }

    // MARK: - Die uebrigen

    @ViewBuilder
    private var others: some View {
        let rest = day.exercises.filter { $0.id != store.currentExercise?.id }
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rest) { exercise in
                    let done = store.doneCount(exercise, on: day)
                    Button {
                        store.chosenExerciseId = exercise.id
                    } label: {
                        HStack {
                            Image(systemName: done >= exercise.sets ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done >= exercise.sets ? Color.accentColor : .secondary)
                            Text(store.machineName(exercise.machineId))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(done)/\(exercise.sets) · " + GymFormat.weight(exercise.weightKg))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gymOther-\(exercise.id)")
                    if exercise.id != rest.last?.id { Divider() }
                }
            }
            .dashboardCard()
        }
    }

    // MARK: - Uhr

    /// Was die Uhr zeigt: das aktuelle Geraet mit Notiz, Satz, Spanne und Gewicht.
    private var watchState: WorkoutCurrent? {
        guard let exercise = store.currentExercise else { return nil }
        let note = store.state?.machine(exercise.machineId)?.note ?? ""
        return WorkoutCurrent(exerciseId: exercise.id, name: store.machineName(exercise.machineId),
                              note: note.isEmpty ? nil : note,
                              set: min(store.doneCount(exercise, on: day) + 1, exercise.sets),
                              sets: exercise.sets, reps: exercise.reps, repsMin: exercise.repsRange?.lowerBound,
                              weightKg: exercise.weightKg)
    }
}
