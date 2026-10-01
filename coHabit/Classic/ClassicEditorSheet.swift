import SwiftUI

/// Neues Habit anlegen - oder ein vorhandenes bearbeiten: dann sind Name und
/// Ziele vorbelegt, und die Art steht fest (aus einem Aufbauen ein Lassen zu
/// machen kehrte jeden Eintrag um; der Dienst laesst es nicht zu).
///
/// Das Formular der Fokus-App, unveraendert - bis auf zwei Dinge aus coHabit:
/// einen Rhythmus, den es nicht kennt (Wochentage, „alle n Tage"), blendet es
/// aus und laesst ihn stehen, und lehnt der Dienst ab, steht seine Meldung im
/// Blatt statt dahinter.
struct ClassicEditorSheet: View {

    let store: ClassicStore
    /// Das Habit, das bearbeitet wird - nil beim Anlegen.
    var editing: ClassicHabit? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: ClassicHabit.Kind = .build
    @State private var goalText = "70000"
    /// Fokus-Zeit in Minuten je Tag - vier Stunden, so hat Felix es bestellt.
    @State private var focusMinutesText = "240"
    /// Nur beim Aufbauen: jeden Tag, oder so-und-so-oft je Woche oder Monat.
    @State private var period: ClassicHabit.Period = .day
    @State private var timesPerPeriod = 1
    @State private var isSaving = false
    @State private var prefilled = false
    /// Die Ablehnung des Dienstes („Diese Quelle hast du nicht.").
    @State private var errorMessage: String?

    private var goal: Int? { Int(goalText.replacingOccurrences(of: ".", with: "")) }
    private var focusMinutes: Int? { Int(focusMinutesText) }

    /// Beim Anlegen immer, beim Bearbeiten nur, wenn das Formular den
    /// Rhythmus des Habits zeigen kann.
    private var showsRhythm: Bool {
        kind == .build && (editing?.hasClassicRhythm ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (kind != .steps || (goal ?? 0) > 0)
            && (kind != .focus || (focusMinutes ?? 0) > 0)
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    ErrorLine(message: errorMessage)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("habitName")
                }
                Section {
                    if editing == nil {
                        Picker("Art", selection: $kind) {
                            ForEach(ClassicHabit.Kind.creatable, id: \.self) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } else {
                        LabeledContent("Art", value: kind.label)
                    }
                } footer: {
                    Text(explanation)
                }
                if showsRhythm {
                    Section("Rhythmus") {
                        Picker("Rhythmus", selection: $period) {
                            ForEach(ClassicHabit.Period.allCases, id: \.self) { period in
                                Text(period.label).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        if period != .day {
                            Stepper(value: $timesPerPeriod, in: 1...period.maxTimes) {
                                Text(period == .week ? "\(timesPerPeriod)× pro Woche"
                                                     : "\(timesPerPeriod)× pro Monat")
                            }
                            .accessibilityIdentifier("timesPerPeriod")
                        }
                    }
                }
                if kind == .steps {
                    Section("Wochenziel") {
                        TextField("Schritte", text: $goalText)
                            .keyboardType(.numberPad)
                    }
                }
                if kind == .focus {
                    Section("Tagesziel in Minuten") {
                        TextField("Minuten", text: $focusMinutesText)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Neues Habit" : "Habit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Anlegen" : "Sichern") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("habitSave")
                }
            }
            .onAppear(perform: prefill)
        }
        .tint(nil as Color?)
    }

    /// Beim Bearbeiten die Felder mit dem Stand des Habits fuellen - einmal,
    /// nicht bei jedem Erscheinen.
    private func prefill() {
        guard let editing, !prefilled else { return }
        prefilled = true
        name = editing.name
        kind = editing.kind
        if let goal = editing.weeklyStepGoal { goalText = String(goal) }
        if let minutes = editing.focusMinutesGoal ?? editing.progress.flatMap({ editing.kind == .focus ? $0.goal : nil }) {
            focusMinutesText = String(minutes)
        }
        period = editing.rhythm
        timesPerPeriod = editing.timesPerPeriod ?? 1
    }

    private var explanation: String {
        switch kind {
        case .build:
            if !showsRhythm {
                // Ein Rhythmus, den das Formular nicht kennt: vom alten Text nur,
                // was fuer jeden Rhythmus stimmt.
                "Abhaken an den Tagen, an denen du es getan hast."
            } else if period == .day {
                "Etwas, das du tun willst. Jeden Tag abhaken - sonst reisst die Straehne um Mitternacht."
            } else {
                "Abhaken an den Tagen, an denen du es getan hast. Die Straehne zaehlt Wochen bzw. Monate, in denen es oft genug war."
            }
        case .quit:    "Etwas, das du lassen willst. Zaehlt von selbst; ein eingetragener Rückfall setzt auf null."
        case .food:    "Gilt als erledigt, wenn 80 % des kcal-Ziels erreicht sind oder Frühstück, Mittag und Abend je einen Eintrag haben."
        case .steps:   "Erreicht, sobald die Schritte der Woche (ab Montag 0:00) das Ziel schaffen. Kommt aus Apple Health."
        case .focus:   "Erreicht, sobald die Fokus-Sessions des Tages zusammen das Ziel schaffen. Kommt aus dem Wald."
        case .goal, .challenge, .unknown: ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = ClassicHabitDraft(form: name.trimmingCharacters(in: .whitespaces),
                                      kind: kind,
                                      stepGoal: goal,
                                      focusMinutes: focusMinutes,
                                      period: showsRhythm ? period : nil,
                                      timesPerPeriod: timesPerPeriod)
        let rejection: String?
        if let editing {
            rejection = await store.update(editing, draft)
        } else {
            rejection = await store.create(draft)
        }
        if let rejection {
            errorMessage = rejection
        } else {
            dismiss()
        }
    }
}
