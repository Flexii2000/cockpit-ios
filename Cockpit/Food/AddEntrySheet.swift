import SwiftUI

/// Eintrag hinzufuegen. Kennt schon die Mahlzeit, aus deren Abschnitt heraus
/// es geoeffnet wurde.
struct AddEntrySheet: View {

    let store: FoodStore
    let meal: Meal?
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selected: Dish?
    @State private var gramsText = ""
    @State private var creatingNew = false
    @State private var showingQuickCapture = false
    @State private var isSaving = false

    @State private var newName = ""
    @State private var newKcal = ""
    @State private var newProtein = ""
    @State private var newCarbs = ""
    @State private var newFat = ""
    @State private var newPortion = ""

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
                    Section("Neues Gericht") {
                        TextField("Name", text: $newName)
                        LabeledContent("kcal / 100 g") { decimalField($newKcal) }
                        LabeledContent("Eiweiß / 100 g") { decimalField($newProtein) }
                        LabeledContent("Kohlenhydrate / 100 g") { decimalField($newCarbs) }
                        LabeledContent("Fett / 100 g") { decimalField($newFat) }
                        LabeledContent("Portion (g, optional)") { decimalField($newPortion) }
                    }
                }

                Section("Menge") {
                    LabeledContent("Gramm") { decimalField($gramsText) }
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
                QuickCaptureSheet(store: store, meal: meal) { dismiss() }
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
            ok = await store.addEntry(dishId: nil, dish: request, grams: grams, meal: meal)
        } else {
            ok = await store.addEntry(dishId: selected?.id, dish: nil, grams: grams, meal: meal)
        }
        if ok { dismiss() }
    }
}
