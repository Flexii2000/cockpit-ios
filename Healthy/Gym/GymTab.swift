import SwiftUI

/// Gym (Felix, 14.10.): Trainingstage mit Geraeten, je Tag und Geraet Gewicht
/// und Saetze × Wiederholungen, Saetze abhaken. „Training starten“ macht daraus
/// die Trainingsansicht (`GymWorkoutView`) mit den Werten der Uhr.
///
/// Jeder Tipp speichert - es gibt keinen Speichern-Knopf. Ohne Netz steht der
/// Haken sofort und geht spaeter raus (Vertrag §6).
struct GymTab: View {

    @State private var store = GymStore()
    @State private var sheet: GymSheet?
    @State private var reordering = false
    /// Der Tag, den jemand im Menue gewaehlt hat - sonst der, der dran ist.
    @State private var chosenDayId: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if store.workout != nil, let day = store.workoutDay {
                    GymWorkoutView(store: store, day: day, sheet: $sheet)
                } else {
                    overview
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .weight) }
            .navigationTitle(store.workout != nil ? (store.workoutDay?.name ?? "Training") : "Gym")
            // Im Training zaehlt jeder Punkt Hoehe - die kleine Leiste reicht.
            .navigationBarTitleDisplayMode(store.workout != nil ? .inline : .automatic)
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                GymSheetView(sheet: sheet, store: store)
            }
            .sheet(isPresented: $reordering) {
                GymReorderSheet(title: "Tage ordnen",
                                items: (store.state?.days ?? []).map { ($0.id, $0.name) }) { ids in
                    store.reorderDays(ids)
                }
            }
        }
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
    }

    // MARK: - Uebersicht

    private var overview: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = store.error {
                    ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                }
                if store.isLoading { LoadingPlaceholder() }
                if let state = store.state {
                    if state.days.isEmpty {
                        emptyState
                    } else {
                        startCard
                        ForEach(state.days) { day in
                            GymDayCard(store: store, day: day, sheet: $sheet)
                        }
                    }
                }
            }
            .padding(16)
            // Platz fuer die schwebende Tab-Leiste, wie im Dashboard.
            .padding(.bottom, 60)
        }
        .refreshable { await store.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Button("Trainingstag anlegen") { sheet = .newDay }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gymAddFirstDay")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Oben: der Tag, der dran ist, und der Knopf. Den Tag wechselt das Menue.
    private var startDay: GymDay? {
        chosenDayId.flatMap { store.state?.day($0) } ?? store.nextDay
    }

    @ViewBuilder
    private var startCard: some View {
        if let next = startDay {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ForEach(store.state?.days ?? []) { day in
                        Button {
                            chosenDayId = day.id
                        } label: {
                            if day.id == next.id {
                                Label(day.name, systemImage: "checkmark")
                            } else {
                                Text(day.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(next.name).font(.title3.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("gymDayMenu")
                Button {
                    chosenDayId = nil
                    store.start(next)
                    WorkoutMirror.shared.start()
                } label: {
                    Label("Training starten", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gymStart")
            }
            .dashboardCard()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if store.workout == nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Trainingstag anlegen", systemImage: "plus") { sheet = .newDay }
                    if (store.state?.days.count ?? 0) > 1 {
                        Button("Tage ordnen", systemImage: "arrow.up.arrow.down") { reordering = true }
                    }
                    Divider()
                    Button("Zugang …") { SetupPresenter.shared.isPresented = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("gymMenu")
            }
        }
    }
}

/// Ein Trainingstag: seine Geraete mit Gewicht, „3×8“, Satz-Kreisen und
/// „letztes Mal“. Ein Tipp auf das Geraet oeffnet es zum Aendern.
struct GymDayCard: View {

    let store: GymStore
    let day: GymDay
    @Binding var sheet: GymSheet?
    @State private var reordering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.name).font(.headline)
                if !day.weekdays.isEmpty {
                    Text(GymFormat.weekdays(day.weekdays))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if store.nextDay?.id == day.id {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("ist dran")
                }
                Spacer()
                Menu {
                    Button("Gerät hinzufügen", systemImage: "plus") { sheet = .addExercise(dayId: day.id) }
                    Button("Bearbeiten", systemImage: "pencil") { sheet = .editDay(dayId: day.id) }
                    if day.exercises.count > 1 {
                        Button("Geräte ordnen", systemImage: "arrow.up.arrow.down") { reordering = true }
                    }
                    Divider()
                    Button("Tag löschen", systemImage: "trash", role: .destructive) {
                        Task { _ = await store.delete(day) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("gymDayMenu-\(day.id)")
            }
            ForEach(day.exercises) { exercise in
                GymExerciseRow(store: store, day: day, exercise: exercise, sheet: $sheet)
                if exercise.id != day.exercises.last?.id { Divider() }
            }
            if day.exercises.isEmpty {
                Button {
                    sheet = .addExercise(dayId: day.id)
                } label: {
                    Label("Gerät hinzufügen", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("gymAddExercise-\(day.id)")
            }
        }
        .dashboardCard()
        .sheet(isPresented: $reordering) {
            GymReorderSheet(title: "Geräte ordnen",
                            items: day.exercises.map { ($0.id, store.machineName($0.machineId)) }) { ids in
                store.reorderExercises(of: day, ids)
            }
        }
    }
}

/// Ein Geraet in der Liste: Name, „3×8 · 40 kg“ (mit Spanne „2×8–10 · 40 kg“),
/// die Satz-Kreise. Die Notiz steht nur im Training und im Blatt.
struct GymExerciseRow: View {

    let store: GymStore
    let day: GymDay
    let exercise: GymExercise
    @Binding var sheet: GymSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                sheet = .exercise(dayId: day.id, exerciseId: exercise.id)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.machineName(exercise.machineId))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(GymFormat.scheme(sets: exercise.sets, reps: exercise.reps, repsMin: exercise.repsMin)
                         + " · " + GymFormat.weight(exercise.weightKg))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gymExercise-\(exercise.id)")
            HStack(spacing: 8) {
                GymSetCircles(store: store, day: day, exercise: exercise, size: 30)
                Spacer(minLength: 4)
                if let last = store.state?.last[exercise.machineId] {
                    Button {
                        sheet = .history(machineId: exercise.machineId)
                    } label: {
                        Text(GymFormat.last(last))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Je Satz ein Kreis; ein Tipp hakt ab, noch einer nimmt zurueck.
struct GymSetCircles: View {

    let store: GymStore
    let day: GymDay
    let exercise: GymExercise
    let size: CGFloat
    /// Im Training mit Spanne die Wiederholungen des naechsten Satzes - die
    /// Kreise der Uebersicht haken mit dem Plan ab.
    var reps: Int?

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(0..<exercise.sets, id: \.self) { index in
                let done = store.isDone(exercise, index, on: day)
                Button {
                    store.toggle(exercise, index, on: day, reps: reps)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(done ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 2)
                            .background(Circle().fill(done ? Color.accentColor : .clear))
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: size * 0.42, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: done)
                .accessibilityLabel("Satz \(index + 1)")
                .accessibilityValue(done ? "erledigt" : "offen")
                .accessibilityIdentifier("gymSet-\(exercise.id)-\(index)")
            }
        }
    }
}

/// „− n +“ wie im Logbook.
struct GymStepper: View {

    let value: String
    let label: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            step("minus", action: minus).accessibilityLabel("\(label): weniger")
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minWidth: 72)
                .accessibilityLabel(label)
                .accessibilityValue(value)
            step("plus", action: plus).accessibilityLabel("\(label): mehr")
        }
    }

    private func step(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
