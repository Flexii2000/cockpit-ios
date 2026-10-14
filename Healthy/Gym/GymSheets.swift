import Charts
import SwiftUI

/// Welches Blatt im Gym offen ist.
enum GymSheet: Identifiable, Hashable {
    case newDay
    case editDay(dayId: String)
    case addExercise(dayId: String)
    case exercise(dayId: String, exerciseId: String)
    case history(machineId: String)

    var id: String {
        switch self {
        case .newDay: "newDay"
        case .editDay(let dayId): "edit-" + dayId
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
            GymDaySheet(initialName: "", initialWeekdays: []) { store.addDay(name: $0, weekdays: $1) }
        case .editDay(let dayId):
            if let day = store.state?.day(dayId) {
                GymDaySheet(initialName: day.name, initialWeekdays: day.weekdays) {
                    store.edit(day, name: $0, weekdays: $1)
                }
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

/// Name und Wochentage eines Tages - fuer einen neuen oder einen vorhandenen.
/// An seinen Wochentagen ist der Tag beim Start vorgewaehlt (Felix, 14.10.).
/// „Fertig“ uebernimmt, Wegwischen laesst alles, wie es war.
struct GymDaySheet: View {

    let initialName: String
    let initialWeekdays: [Int]
    let save: (String, [Int]) -> Void

    @State private var name = ""
    @State private var weekdays: Set<Int> = []
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
                Section {
                    HStack(spacing: 0) {
                        ForEach(1...7, id: \.self) { weekday in
                            weekdayButton(weekday)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Trainingstag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: done)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("gymDayDone")
                }
            }
        }
        .presentationDetents([.height(270)])
        .onAppear {
            name = initialName
            weekdays = Set(initialWeekdays)
            // Neu: gleich tippen. Vorhanden: erst die Wochentage zeigen, nicht die Tastatur.
            focused = initialName.isEmpty
        }
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let on = weekdays.contains(weekday)
        return Button {
            if on { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
        } label: {
            Text(GymFormat.weekdayNames[weekday - 1])
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.white : Color.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                .contentShape(Circle())
        }
        // Sonst nimmt der Form-Eintrag jeden Tipp und schaltet den ersten Knopf.
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityValue(on ? "ausgewählt" : "")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("gymWeekday-\(weekday)")
    }

    private func done() {
        save(name, weekdays.sorted())
        dismiss()
    }
}

/// Ein Geraet an den Tag: eines der eigenen (der Verlauf haengt am Geraet),
/// eines aus der Geraeteliste des Dienstes oder ein ganz neues - die Suche
/// filtert alles, und was es nirgends gibt, laesst sich als eigenes anlegen.
struct GymAddExerciseSheet: View {

    let store: GymStore
    let day: GymDay

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ name: String) -> Bool {
        trimmed.isEmpty || name.localizedStandardContains(trimmed)
    }

    /// Die eigenen Geraete, die an diesem Tag noch fehlen.
    private var own: [GymMachine] {
        let used = Set(day.exercises.map(\.machineId))
        return (store.state?.machines ?? [])
            .filter { !$0.archived && !used.contains($0.id) && matches($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Die Geraeteliste ohne das, was es schon als eigenes Geraet gibt - das
    /// steht oben (oder ist an diesem Tag schon dran).
    private var catalog: [GymCatalogGroup] {
        let taken = Set((store.state?.machines ?? []).filter { !$0.archived }.map { $0.name.lowercased() })
        return (store.state?.catalog ?? []).compactMap { group in
            let entries = group.entries.filter { !taken.contains($0.lowercased()) && matches($0) }
            return entries.isEmpty ? nil : GymCatalogGroup(name: group.name, entries: entries)
        }
    }

    /// Was gesucht wird, wenn es das weder als eigenes Geraet noch in der Liste gibt.
    private var newName: String? {
        guard !trimmed.isEmpty else { return nil }
        let known = (store.state?.machines ?? []).map(\.name) + (store.state?.catalog ?? []).flatMap(\.entries)
        return known.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            List {
                if let newName {
                    Section {
                        Button {
                            add(name: newName)
                        } label: {
                            Label("„\(newName)“ hinzufügen", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("gymAddNewMachine")
                    }
                }
                if !own.isEmpty {
                    Section("Deine Geräte") {
                        ForEach(own) { machine in
                            row(machine.name, id: "gymOwn-\(machine.id)") {
                                store.addExercise(to: day, machineId: machine.id, newName: nil)
                                dismiss()
                            }
                        }
                    }
                }
                ForEach(catalog, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.entries, id: \.self) { entry in
                            row(entry, id: "gymPick-\(entry)") { add(name: entry) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Gerät suchen")
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private func row(_ name: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        // Sonst faerbt die Liste jeden Eintrag in der Akzentfarbe - bei rund 65 ein blaues Feld.
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Aus der Liste oder neu: `addExercise` nimmt ein gleichnamiges Geraet,
    /// wenn es das schon gibt.
    private func add(name: String) {
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

/// Gewicht als Zahl, Saetze und Wiederholungen mit „− n +“ - im Blatt und in
/// der Trainingsansicht dieselben Regeln.
struct GymPlanControls: View {

    let store: GymStore
    let dayId: String
    let exercise: GymExercise

    var body: some View {
        VStack(spacing: 12) {
            row("Gewicht") {
                GymWeightField(kg: exercise.weightKg) { kg in change { $0.weightKg = kg } }
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

/// Das Gewicht zum Eintippen (Felix, 14.10.: eine Zahl statt „− n +“).
///
/// Uebernommen wird beim Verlassen des Felds und mit „Fertig“ ueber der
/// Tastatur - nicht bei jeder Ziffer, sonst gingen fuer „37,5“ erst 3, dann 37
/// an den Dienst. Unsinn oder mehr als 500 kg: das alte Gewicht kommt zurueck.
struct GymWeightField: View {

    let kg: Double
    let save: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(width: 80)
                .focused($focused)
                .accessibilityLabel("Gewicht in Kilogramm")
                .accessibilityIdentifier("gymWeight")
            Text("kg")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { text = GymFormat.weightField(kg) }
        .onChange(of: kg) { _, new in
            if !focused { text = GymFormat.weightField(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        // Blatt mit „Fertig“ zu, waehrend die Tastatur offen war.
        .onDisappear(perform: commit)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("Fertig") { focused = false }
                        .accessibilityIdentifier("gymWeightDone")
                }
            }
        }
    }

    private func commit() {
        guard let value = GymFormat.parseWeight(text) else {
            text = GymFormat.weightField(kg)
            return
        }
        text = GymFormat.weightField(value)
        if value != kg { save(value) }
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
