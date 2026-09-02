import SwiftUI

/// Neues Habit anlegen.
struct HabitEditorSheet: View {

    let store: HabitsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: HabitStatus.Kind = .build
    @State private var goalText = "70000"
    @State private var isSaving = false

    private var goal: Int? { Int(goalText.replacingOccurrences(of: ".", with: "")) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (kind != .steps || (goal ?? 0) > 0)
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("habitName")
                }
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(HabitStatus.Kind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text(explanation)
                }
                if kind == .steps {
                    Section("Wochenziel") {
                        TextField("Schritte", text: $goalText)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Neues Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var explanation: String {
        switch kind {
        case .build: "Etwas, das du tun willst. Jeden Tag abhaken - sonst reisst die Straehne um Mitternacht."
        case .quit:  "Etwas, das du lassen willst. Zaehlt von selbst; ein eingetragener Rückfall setzt auf null."
        case .food:  "Gilt als erledigt, wenn 80 % des kcal-Ziels erreicht sind oder Frühstück, Mittag und Abend je einen Eintrag haben."
        case .steps: "Erreicht, sobald die Schritte der Woche (ab Montag 0:00) das Ziel schaffen. Kommt aus Apple Health."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let ok = await store.create(name: name.trimmingCharacters(in: .whitespaces),
                                    kind: kind,
                                    weeklyStepGoal: kind == .steps ? goal : nil)
        if ok { dismiss() }
    }
}
