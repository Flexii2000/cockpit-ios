import Charts
import SwiftUI

/// Welches Blatt im Gym offen ist.
enum GymSheet: Identifiable, Hashable {
    case newDay
    case renameDay(dayId: String)
    case addExercise(dayId: String)
    case exercise(dayId: String, exerciseId: String)
    case history(machineId: String)

    var id: String {
        switch self {
        case .newDay: "newDay"
        case .renameDay(let dayId): "rename-" + dayId
        case .addExercise(let dayId): "add-" + dayId
        case .exercise(_, let exerciseId): "exercise-" + exerciseId
        case .history(let machineId): "history-" + machineId
        }
    }
}

struct GymSheetView: View {

    let sheet: GymSheet
    let store: GymStore

    var body: some View {
        switch sheet {
        case .newDay:
            GymNameSheet(title: "Trainingstag", initial: "") { store.addDay(name: $0) }
        case .renameDay(let dayId):
            if let day = store.state?.day(dayId) {
                GymNameSheet(title: "Trainingstag", initial: day.name) { store.rename(day, to: $0) }
            }
        case .addExercise(let dayId):
            if let day = store.state?.day(dayId) {
                GymAddExerciseSheet(store: store, day: day)
            }
        case .exercise(let dayId, let exerciseId):
            if let day = store.state?.day(dayId), let exercise = day.exercises.first(where: { $0.id == exerciseId }) {
                GymExerciseSheet(store: store, day: day, exercise: exercise)
            }
        case .history(let machineId):
            GymHistorySheet(store: store, machineId: machineId)
        }
    }
}

/// Ein Name - fuer einen neuen oder umbenannten Tag. „Fertig“ uebernimmt,
/// Wegwischen laesst alles, wie es war.
struct GymNameSheet: View {

    let title: String
    let initial: String
    let save: (String) -> Void

    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(done)
                    .accessibilityIdentifier("gymName")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: done)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(200)])
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func done() {
        save(name)
        dismiss()
    }
}

/// Ein Geraet an den Tag: eines, das es schon gibt (der Verlauf haengt am
/// Geraet), oder ein neues.
struct GymAddExerciseSheet: View {

    let store: GymStore
    let day: GymDay

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var available: [GymMachine] {
        let used = Set(day.exercises.map(\.machineId))
        return (store.state?.machines ?? [])
            .filter { !$0.archived && !used.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Neues Gerät", text: $name)
                            .submitLabel(.done)
                            .onSubmit(addNew)
                            .accessibilityIdentifier("gymNewMachine")
                        Button("Hinzufügen", action: addNew)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("gymAddNewMachine")
                    }
                }
                if !available.isEmpty {
                    Section("Vorhanden") {
                        ForEach(available) { machine in
                            Button(machine.name) {
                                store.addExercise(to: day, machineId: machine.id, newName: nil)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func addNew() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addExercise(to: day, machineId: nil, newName: name)
        dismiss()
    }
}

/// Ein Geraet an einem Tag aendern: Gewicht in 2,5-kg-Schritten, Saetze und
/// Wiederholungen. Jeder Tipp speichert.
struct GymExerciseSheet: View {

    let store: GymStore
    let day: GymDay
    let exercise: GymExercise

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    /// Immer der aktuelle Stand - nach jedem Tipp steht er im Overlay.
    private var current: GymExercise {
        store.state?.day(day.id)?.exercises.first { $0.id == exercise.id } ?? exercise
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { store.rename(machineId: current.machineId, to: name) }
                }
                Section {
                    GymPlanControls(store: store, dayId: day.id, exercise: current)
                }
                if let last = store.state?.last[current.machineId] {
                    Section {
                        NavigationLink {
                            GymHistoryView(store: store, machineId: current.machineId)
                        } label: {
                            Text(GymFormat.last(last))
                        }
                    }
                }
                Section {
                    Button("Vom Tag entfernen", role: .destructive) {
                        Task {
                            if await store.remove(current, from: day) { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(store.machineName(current.machineId))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        store.rename(machineId: current.machineId, to: name)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { name = store.machineName(exercise.machineId) }
    }
}

/// Gewicht, Saetze, Wiederholungen mit „− n +“ - im Blatt und in der
/// Trainingsansicht dieselben Regeln.
struct GymPlanControls: View {

    let store: GymStore
    let dayId: String
    let exercise: GymExercise

    static let weightStep = 2.5

    var body: some View {
        VStack(spacing: 12) {
            row("Gewicht") {
                GymStepper(value: GymFormat.weight(exercise.weightKg), label: "Gewicht",
                           minus: { change { $0.weightKg = max(0, $0.weightKg - Self.weightStep) } },
                           plus: { change { $0.weightKg = min(500, $0.weightKg + Self.weightStep) } })
            }
            row("Sätze") {
                GymStepper(value: "\(exercise.sets)", label: "Sätze",
                           minus: { change { $0.sets = max(1, $0.sets - 1) } },
                           plus: { change { $0.sets = min(10, $0.sets + 1) } })
            }
            row("Wiederholungen") {
                GymStepper(value: "\(exercise.reps)", label: "Wiederholungen",
                           minus: { change { $0.reps = max(1, $0.reps - 1) } },
                           plus: { change { $0.reps = min(100, $0.reps + 1) } })
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

    private func change(_ edit: (inout GymExercise) -> Void) {
        var changed = exercise
        edit(&changed)
        guard changed != exercise else { return }
        store.update(changed, in: dayId)
    }
}

/// Der Verlauf eines Geraets als Blatt.
struct GymHistorySheet: View {
    let store: GymStore
    let machineId: String

    var body: some View {
        NavigationStack {
            GymHistoryView(store: store, machineId: machineId)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Je Besuch der schwerste Satz (rechnet der Dienst) - als Linie, darunter die Liste.
struct GymHistoryView: View {

    let store: GymStore
    let machineId: String

    @State private var points: [GymHistoryPoint]?

    var body: some View {
        List {
            if let points {
                if points.isEmpty {
                    Text("–").foregroundStyle(.secondary)
                } else {
                    Section {
                        Chart(points) { point in
                            LineMark(x: .value("Tag", point.date.startOfDay(), unit: .day),
                                     y: .value("kg", point.weightKg))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Tag", point.date.startOfDay(), unit: .day),
                                      y: .value("kg", point.weightKg))
                                .symbolSize(24)
                        }
                        .chartYAxisLabel("kg")
                        .frame(height: 180)
                        .padding(.vertical, 8)
                    }
                    Section {
                        ForEach(points.reversed()) { point in
                            HStack {
                                Text(point.date.short).monospacedDigit()
                                Spacer()
                                Text(GymFormat.scheme(sets: point.sets, reps: point.reps) + " · "
                                     + GymFormat.weight(point.weightKg))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                LoadingPlaceholder()
            }
        }
        .navigationTitle(store.machineName(machineId))
        .navigationBarTitleDisplayMode(.inline)
        .task { points = await store.history(of: machineId) }
    }
}

/// Reihenfolge per Ziehen - fuer Tage und fuer die Geraete eines Tages.
struct GymReorderSheet: View {

    let title: String
    let items: [(id: String, name: String)]
    let save: ([String]) -> Void

    @State private var order: [Item] = []
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable, Hashable {
        let id: String
        let name: String
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { item in
                    Text(item.name)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        save(order.map(\.id))
                        dismiss()
                    }
                }
            }
        }
        .onAppear { order = items.map { Item(id: $0.id, name: $0.name) } }
    }
}
