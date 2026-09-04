import SwiftUI

/// Einen Eintrag berichtigen: Menge, Mahlzeit, Tag.
///
/// Das Gericht ist hier bewusst nicht aenderbar. Sonst hinge an dem Eintrag
/// ploetzlich ein anderer Name mit anderen Werten, und die Tagessumme von
/// damals passte nicht mehr zu dem, was eingetragen wurde. Wer etwas anderes
/// gegessen hat, loescht und traegt neu ein.
struct EditEntrySheet: View {

    let store: FoodStore
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss

    @State private var gramsText: String
    @State private var meal: Meal
    @State private var date: Date
    @State private var isSaving = false

    init(store: FoodStore, entry: FoodEntry) {
        self.store = store
        self.entry = entry
        _gramsText = State(initialValue: entry.grams.whole)
        _meal = State(initialValue: entry.meal ?? .snack)
        _date = State(initialValue: entry.date.startOfDay())
    }

    private var grams: Double? { AddEntrySheet.number(gramsText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Gericht") {
                        Text(entry.name).foregroundStyle(.secondary)
                    }
                    LabeledContent("Menge") {
                        TextField("g", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(Meal.allCases) { meal in
                            Text(meal.label).tag(meal)
                        }
                    }
                    DatePicker("Tag", selection: $date, displayedComponents: .date)
                } footer: {
                    if let grams, let per100g = entry.per100g {
                        Text("\(per100g.scaled(gramsOf: grams).kcal.whole) kcal bei \(grams.whole) g")
                    }
                }
            }
            .navigationTitle("Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled((grams ?? 0) <= 0 || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let grams, grams > 0 else { return }
        isSaving = true
        defer { isSaving = false }
        let day = CalendarDate(date: date)
        if await store.updateEntry(entry, grams: grams, meal: meal,
                                   date: day == entry.date ? nil : day) {
            dismiss()
        }
    }
}
