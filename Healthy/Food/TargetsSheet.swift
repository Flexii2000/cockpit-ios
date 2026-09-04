import SwiftUI

/// Tagesziele und ihre Aufteilung auf die Mahlzeiten.
struct TargetsSheet: View {

    let store: FoodStore
    @Environment(\.dismiss) private var dismiss

    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    /// Anteile in Prozent, damit die Mahlzeitenziele mitwandern, wenn sich
    /// das Tagesziel aendert.
    @State private var shares: [Meal: String] = [:]
    @State private var isSaving = false

    private var shareSum: Double {
        Meal.allCases.reduce(0) { $0 + (AddEntrySheet.number(shares[$1] ?? "") ?? 0) }
    }

    /// Der Server nimmt eine Aufteilung nur an, wenn **alle vier** Mahlzeiten
    /// drinstehen und die Summe 100 % ergibt (`validShares` in FoodService).
    /// Das hier vorher zu pruefen erspart eine Fehlermeldung fuer etwas, das
    /// man auf dem Bildschirm sieht.
    private var sharesAreValid: Bool {
        shareSum == 0 || abs(shareSum - 100) <= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tagesziele") {
                    LabeledContent("kcal") { field($kcal) }
                    LabeledContent("Eiweiß (g)") { field($protein) }
                    LabeledContent("Kohlenhydrate (g)") { field($carbs) }
                    LabeledContent("Fett (g)") { field($fat) }
                }

                Section {
                    ForEach(Meal.allCases) { meal in
                        LabeledContent(meal.label) {
                            field(Binding(
                                get: { shares[meal] ?? "" },
                                set: { shares[meal] = $0 }))
                        }
                    }
                } header: {
                    Text("Aufteilung des kcal-Ziels (%)")
                } footer: {
                    Text(shareSum == 0
                         ? "Ohne Angabe bleibt die bisherige Aufteilung."
                         : "Summe: \(shareSum.whole) %")
                    .foregroundStyle(shareSum > 0 && abs(shareSum - 100) > 0.5 ? .orange : .secondary)
                }
            }
            .navigationTitle("Tagesziele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(isSaving || !sharesAreValid)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func field(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
    }

    private func fill() {
        guard let day = store.day, kcal.isEmpty else { return }
        kcal = day.targets.kcal.whole
        protein = day.targets.proteinG.oneDecimal
        carbs = day.targets.carbsG.oneDecimal
        fat = day.targets.fatG.oneDecimal
        let total = day.targets.kcal
        guard total > 0 else { return }
        for (meal, value) in day.targetsByMeal {
            shares[meal] = (value / total * 100).whole
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        // Alle vier Mahlzeiten muessen mit - eine fehlende weist der Server
        // ab, auch wenn ihr Anteil null waere. Und er rechnet mit Anteilen,
        // nicht mit Prozent.
        var mealShares: [String: Double] = [:]
        if shareSum > 0 {
            for meal in Meal.allCases {
                mealShares[meal.rawValue] = (AddEntrySheet.number(shares[meal] ?? "") ?? 0) / 100
            }
        }
        let request = TargetsRequest(kcal: AddEntrySheet.number(kcal),
                                     proteinG: AddEntrySheet.number(protein),
                                     carbsG: AddEntrySheet.number(carbs),
                                     fatG: AddEntrySheet.number(fat),
                                     mealShares: mealShares.isEmpty ? nil : mealShares)
        if await store.updateTargets(request) { dismiss() }
    }
}
