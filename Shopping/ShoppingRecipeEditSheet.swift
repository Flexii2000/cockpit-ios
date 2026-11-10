import SwiftUI

/// Ein Rezept anlegen oder aendern. Zutaten und Schritte sind Zeilen; die leere
/// Zeile am Ende nimmt die naechste - kein Knopf, kein Menue. Alles ausser Name
/// und Zutaten darf leer bleiben: dann ist es ein Gericht wie frueher.
struct ShoppingRecipeEditSheet: View {

    let store: ShoppingStore
    let dish: ShoppingDish?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var portions: String
    @State private var minutes: String
    @State private var rows: [IngredientRow]
    @State private var newIngredient = ""
    @State private var newQuantity = ""
    @State private var newUnit: ShoppingQuantity.Unit = .piece
    @State private var steps: [StepRow]
    @State private var newStep = ""
    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var grams: String
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case newIngredient, newStep
    }

    struct IngredientRow: Identifiable {
        let id = UUID()
        var name: String
        var amount: String
        var unit: ShoppingQuantity.Unit
        /// Hat man meist da - beim „Auf die Liste“ nicht vorgewaehlt.
        var pantry: Bool

        init(name: String, quantity: String?, pantry: Bool = false) {
            self.name = name
            let parsed = ShoppingQuantity.parse(quantity)
            amount = parsed?.amount ?? quantity ?? ""
            unit = parsed?.unit ?? .piece
            self.pantry = pantry
        }
    }

    struct StepRow: Identifiable {
        let id = UUID()
        var text: String
    }

    init(store: ShoppingStore, dish: ShoppingDish?) {
        self.store = store
        self.dish = dish
        _name = State(initialValue: dish?.name ?? "")
        _portions = State(initialValue: dish?.basePortions.map(String.init) ?? "")
        _minutes = State(initialValue: dish?.minutes.map(String.init) ?? "")
        _rows = State(initialValue: (dish?.ingredients ?? []).map {
            IngredientRow(name: $0.name, quantity: $0.quantity, pantry: $0.isPantry)
        })
        _steps = State(initialValue: (dish?.stepList ?? []).map { StepRow(text: $0) })
        _kcal = State(initialValue: ShoppingRecipeFormat.field(dish?.nutrition?.kcal))
        _protein = State(initialValue: ShoppingRecipeFormat.field(dish?.nutrition?.proteinG))
        _carbs = State(initialValue: ShoppingRecipeFormat.field(dish?.nutrition?.carbsG))
        _fat = State(initialValue: ShoppingRecipeFormat.field(dish?.nutrition?.fatG))
        _grams = State(initialValue: ShoppingRecipeFormat.field(dish?.gramsPerPortion))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("recipeName")
                    numberRow("Portionen", text: $portions, identifier: "recipePortions")
                    numberRow("Minuten", text: $minutes, identifier: "recipeMinutes")
                }
                Section("Zutaten") {
                    ForEach($rows) { $row in
                        HStack {
                            TextField("Zutat", text: $row.name)
                            QuantityField(amount: $row.amount, unit: $row.unit)
                            pantryButton($row.pantry)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    HStack {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.tertiary)
                        TextField("Zutat", text: $newIngredient)
                            .focused($focus, equals: .newIngredient)
                            .submitLabel(.next)
                            .onSubmit { addIngredient() }
                            .accessibilityIdentifier("newIngredient")
                        QuantityField(amount: $newQuantity, unit: $newUnit, onSubmit: addIngredient)
                    }
                }
                Section("Schritte") {
                    ForEach($steps) { $step in
                        TextField("Schritt", text: $step.text, axis: .vertical)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.tertiary)
                        TextField("Schritt", text: $newStep, axis: .vertical)
                            .focused($focus, equals: .newStep)
                            .accessibilityIdentifier("newStep")
                            .onChange(of: newStep) { _, text in
                                // Im mehrzeiligen Feld schickt die Zeilentaste nichts
                                // ab - sie beendet hier den Schritt.
                                if text.contains("\n") { addStep() }
                            }
                    }
                }
                Section("Nährwerte je Portion") {
                    numberRow("kcal", text: $kcal, decimal: true, identifier: "recipeKcal")
                    numberRow("Eiweiß (g)", text: $protein, decimal: true, identifier: "recipeProtein")
                    numberRow("Kohlenhydrate (g)", text: $carbs, decimal: true, identifier: "recipeCarbs")
                    numberRow("Fett (g)", text: $fat, decimal: true, identifier: "recipeFat")
                    numberRow("Gramm je Portion", text: $grams, decimal: true, identifier: "recipeGrams")
                }
            }
            .navigationTitle(dish == nil ? "Neues Rezept" : "Rezept")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("saveRecipe")
                }
            }
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, decimal: Bool = false,
                           identifier: String) -> some View {
        LabeledContent(label) {
            // Das Feld reicht bis an die Beschriftung: ein Tipp irgendwo rechts von
            // ihr setzt den Cursor, nicht nur einer auf den schmalen Strich am Rand.
            TextField("–", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
        }
    }

    /// Das Haus: „hat man zu Hause“. Ein Symbol statt eines Schalters je Zeile -
    /// der braeuchte eine zweite Zeile unter jeder Zutat.
    private func pantryButton(_ pantry: Binding<Bool>) -> some View {
        Button {
            pantry.wrappedValue.toggle()
        } label: {
            Image(systemName: pantry.wrappedValue ? "house.fill" : "house")
                .foregroundStyle(pantry.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Vorrat")
        .accessibilityValue(pantry.wrappedValue ? "ja" : "nein")
    }

    private func addIngredient() {
        var n = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        var q = ShoppingQuantity.compose(newQuantity, unit: newUnit)
        if q == nil {
            let split = ShoppingQuantity.split(n)
            n = split.name
            q = split.quantity?.text
        }
        rows.append(IngredientRow(name: n, quantity: q))
        newIngredient = ""
        newQuantity = ""
        newUnit = .piece
        focus = .newIngredient
    }

    private func addStep() {
        let text = newStep.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        newStep = ""
        guard !text.isEmpty else { return }
        steps.append(StepRow(text: text))
        focus = .newStep
    }

    /// Was im Blatt steht, als Rumpf fuer den Dienst. Jedes Feld geht mit - beim
    /// Aendern heisst ein fehlendes „nicht anfassen“, also schickt ein geleertes
    /// Feld den leeren Wert (0, `[]`, `{}`), der beim Dienst loescht.
    private func draft() -> ShoppingDishDraft {
        let ingredients = rows.compactMap { row -> ShoppingIngredient? in
            let n = row.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return nil }
            return ShoppingIngredient(name: n, quantity: ShoppingQuantity.compose(row.amount, unit: row.unit),
                                      pantry: row.pantry)
        }
        let texts = steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let values = ShoppingNutrition(kcal: ShoppingRecipeFormat.value(kcal),
                                       proteinG: ShoppingRecipeFormat.value(protein),
                                       carbsG: ShoppingRecipeFormat.value(carbs),
                                       fatG: ShoppingRecipeFormat.value(fat))
        return ShoppingDishDraft(name: name.trimmingCharacters(in: .whitespaces),
                                 ingredients: ingredients,
                                 portions: Int(portions.trimmingCharacters(in: .whitespaces)) ?? 0,
                                 minutes: Int(minutes.trimmingCharacters(in: .whitespaces)) ?? 0,
                                 steps: texts,
                                 nutrition: values,
                                 gramsPerPortion: ShoppingRecipeFormat.value(grams) ?? 0)
    }

    private func save() async {
        // Was noch in den leeren Zeilen steht, zaehlt mit - sonst ginge die letzte
        // Zutat verloren, weil man Sichern statt Enter getippt hat.
        addIngredient()
        addStep()
        focus = nil
        isSaving = true
        defer { isSaving = false }
        let body = draft()
        let ok: Bool
        if let dish {
            ok = await store.updateDish(dish, draft: body)
        } else {
            ok = await store.createDish(body)
        }
        if ok { dismiss() }
    }
}
