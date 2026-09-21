import SwiftUI

/// Eintrag hinzufuegen. Kennt schon die Mahlzeit, aus deren Abschnitt heraus
/// es geoeffnet wurde - oder fragt danach, wenn es vom Scanner kommt und
/// keinen Abschnitt gibt.
struct AddEntrySheet: View {

    let store: FoodStore
    let meal: Meal?
    /// Was der Scanner mitbringt; `nil`, wenn das Blatt ueber „+" aufging.
    let scan: ScanResult?
    @Environment(\.dismiss) private var dismiss

    @State private var search: String
    @State private var selected: Dish?
    @State private var gramsText: String
    @State private var creatingNew: Bool
    /// Vom Scanner aus gibt es keinen Abschnitt, der die Mahlzeit vorgibt -
    /// dann steht hier die zur Uhrzeit naheliegende, umstellbar.
    @State private var chosenMeal: Meal
    @State private var showingQuickCapture = false
    @State private var isSaving = false

    @State private var newName: String
    @State private var newKcal: String
    @State private var newProtein: String
    @State private var newCarbs: String
    @State private var newFat: String
    @State private var newPortion: String

    init(store: FoodStore, meal: Meal?, scan: ScanResult? = nil) {
        self.store = store
        self.meal = meal
        self.scan = scan
        _chosenMeal = State(initialValue: meal
            ?? Meal.suggested(hour: Calendar.current.component(.hour, from: Date())))

        var prefill = EntryPrefill()
        if let product = scan?.product {
            prefill = EntryPrefill(product: product, dishes: store.dishes)
        } else if scan != nil {
            // Nicht in der Datenbank: dann wenigstens gleich das leere
            // Formular fuer ein neues Gericht, statt erst den Umschalter zu
            // suchen.
            prefill.creatingNew = true
        }
        _search = State(initialValue: prefill.search)
        _selected = State(initialValue: prefill.selected)
        _gramsText = State(initialValue: prefill.grams)
        _creatingNew = State(initialValue: prefill.creatingNew)
        _newName = State(initialValue: prefill.name)
        _newKcal = State(initialValue: prefill.kcal)
        _newProtein = State(initialValue: prefill.protein)
        _newCarbs = State(initialValue: prefill.carbs)
        _newFat = State(initialValue: prefill.fat)
        _newPortion = State(initialValue: prefill.portion)
    }

    private var grams: Double? { Self.number(gramsText) }

    private var filteredDishes: [Dish] {
        guard !search.isEmpty else { return store.dishes }
        return store.dishes.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var canSave: Bool {
        guard let grams, grams > 0, !isSaving else { return false }
        return creatingNew ? !newName.trimmingCharacters(in: .whitespaces).isEmpty
                           : selected != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.quickCaptureAvailable {
                    Section {
                        Button {
                            showingQuickCapture = true
                        } label: {
                            Label("Schnellerfassung", systemImage: "text.bubble")
                        }
                    } footer: {
                        Text("Freitext eingeben, den Rest macht der Server.")
                    }
                }

                if !creatingNew {
                    Section("Gericht") {
                        TextField("Suchen …", text: $search)
                            .autocorrectionDisabled()
                        ForEach(filteredDishes) { dish in
                            Button {
                                selected = dish
                                if gramsText.isEmpty, let portion = dish.portionG {
                                    gramsText = portion.whole
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dish.name).foregroundStyle(.primary)
                                        Text("\(dish.per100g.kcal.whole) kcal / 100 g")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected?.id == dish.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                if creatingNew {
                    Section {
                        TextField("Name", text: $newName)
                        LabeledContent("kcal / 100 g") { decimalField($newKcal) }
                        LabeledContent("Eiweiß / 100 g") { decimalField($newProtein) }
                        LabeledContent("Kohlenhydrate / 100 g") { decimalField($newCarbs) }
                        LabeledContent("Fett / 100 g") { decimalField($newFat) }
                        LabeledContent("Portion (g, optional)") { decimalField($newPortion) }
                    } header: {
                        Text("Neues Gericht")
                    } footer: {
                        // Nur der Code, kein Erklaertext - den Rest tippt man selbst.
                        if let scan, scan.product == nil {
                            Text("Nicht in der Datenbank: \(scan.code)")
                        }
                    }
                }

                Section("Menge") {
                    LabeledContent("Gramm") { decimalField($gramsText) }
                    if meal == nil {
                        Picker("Mahlzeit", selection: $chosenMeal) {
                            ForEach(Meal.allCases) { meal in
                                Text(meal.label).tag(meal)
                            }
                        }
                    }
                    if let portion = selected?.portionG, !creatingNew {
                        HStack {
                            ForEach([0.5, 1.0, 2.0], id: \.self) { factor in
                                Button("\(Self.portionLabel(factor)) (\((portion * factor).whole) g)") {
                                    gramsText = (portion * factor).whole
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Gericht neu anlegen", isOn: $creatingNew.animation())
                }
            }
            .navigationTitle(meal?.label ?? "Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Eintragen") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingQuickCapture) {
                // Ist der Auftrag weg, hat dieses Blatt nichts mehr zu tun.
                QuickCaptureSheet(store: store, meal: chosenMeal) { dismiss() }
            }
        }
    }

    private func decimalField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
    }

    private static func portionLabel(_ factor: Double) -> String {
        switch factor {
        case 0.5: "½ Portion"
        case 2.0: "2 Portionen"
        default:  "1 Portion"
        }
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func save() async {
        guard let grams else { return }
        isSaving = true
        defer { isSaving = false }
        let ok: Bool
        if creatingNew {
            let request = DishRequest(name: newName.trimmingCharacters(in: .whitespaces),
                                      kcal: Self.number(newKcal),
                                      proteinG: Self.number(newProtein),
                                      carbsG: Self.number(newCarbs),
                                      fatG: Self.number(newFat),
                                      portionG: Self.number(newPortion))
            ok = await store.addEntry(dishId: nil, dish: request, grams: grams, meal: chosenMeal)
        } else {
            ok = await store.addEntry(dishId: selected?.id, dish: nil, grams: grams, meal: chosenMeal)
        }
        if ok { dismiss() }
    }
}

/// Womit das Blatt aufgeht, wenn ein Scan dahintersteht. Getrennt vom Blatt,
/// damit sich die Regel pruefen laesst: ein Name, den die Merkliste schon
/// kennt, waehlt das vorhandene Gericht; ein neuer fuellt das Formular.
struct EntryPrefill: Equatable {
    var search = ""
    var selected: Dish?
    var grams = ""
    var creatingNew = false
    var name = ""
    var kcal = ""
    var protein = ""
    var carbs = ""
    var fat = ""
    var portion = ""

    init() {}

    init(product: ScannedProduct, dishes: [Dish]) {
        let displayName = product.displayName
        if let known = dishes.first(where: { $0.name == displayName }) {
            // Schon einmal gescannt: das vorhandene Gericht, kein zweites mit
            // demselben Namen in der Merkliste.
            selected = known
            search = displayName
            grams = Self.text(product.servingG ?? known.portionG)
        } else {
            creatingNew = true
            name = displayName
            kcal = Self.text(product.kcal)
            protein = Self.text(product.proteinG)
            carbs = Self.text(product.carbsG)
            fat = Self.text(product.fatG)
            portion = Self.text(product.servingG)
            grams = Self.text(product.servingG)
        }
    }

    /// Hoechstens eine Nachkommastelle und kein Tausenderpunkt - so liest
    /// `AddEntrySheet.number` es wieder ein.
    static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}

extension Meal {
    /// Welche Mahlzeit um diese Uhrzeit die naheliegende ist - fuer Eintraege,
    /// die nicht aus einem Mahlzeiten-Abschnitt heraus entstehen (Scanner).
    static func suggested(hour: Int) -> Meal {
        switch hour {
        case 5..<11:  .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default:      .snack
        }
    }
}
