import SwiftUI

/// Die Gerichte-Merkliste.
struct DishListView: View {

    let store: FoodStore
    @State private var editing: Dish?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(store.dishes) { dish in
                    Button {
                        editing = dish
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dish.name).foregroundStyle(.primary)
                            Text(summary(dish))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { store.dishes[$0] }
                    Task { for dish in doomed { await store.deleteDish(dish) } }
                }
            } footer: {
                Text("Änderungen gelten für neue Einträge. Bereits eingetragene "
                     + "Portionen behalten die Werte, mit denen sie erfasst wurden.")
            }
        }
        .navigationTitle("Gerichte")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { dish in
            DishEditSheet(store: store, dish: dish)
        }
        .sheet(isPresented: $creating) {
            DishEditSheet(store: store, dish: nil)
        }
    }

    private func summary(_ dish: Dish) -> String {
        var parts = ["\(dish.per100g.kcal.whole) kcal / 100 g"]
        if let portion = dish.portionG {
            parts.append("Portion \(portion.whole) g")
        }
        return parts.joined(separator: " · ")
    }
}

/// Gericht anlegen oder aendern - dasselbe Formular, `dish == nil` heisst neu.
struct DishEditSheet: View {

    let store: FoodStore
    let dish: Dish?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var portion = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Je 100 g") {
                    LabeledContent("kcal") { field($kcal) }
                    LabeledContent("Eiweiß") { field($protein) }
                    LabeledContent("Kohlenhydrate") { field($carbs) }
                    LabeledContent("Fett") { field($fat) }
                }
                Section {
                    LabeledContent("Portion (g)") { field($portion) }
                } footer: {
                    Text("Optional. Ist sie gesetzt, gibt es beim Eintragen "
                         + "Knöpfe für halbe, ganze und doppelte Portion.")
                }
            }
            .navigationTitle(dish == nil ? "Neues Gericht" : "Gericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
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
        guard let dish, name.isEmpty else { return }
        name = dish.name
        kcal = dish.per100g.kcal.oneDecimal
        protein = dish.per100g.proteinG.oneDecimal
        carbs = dish.per100g.carbsG.oneDecimal
        fat = dish.per100g.fatG.oneDecimal
        portion = dish.portionG?.whole ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let request = DishRequest(name: name.trimmingCharacters(in: .whitespaces),
                                  kcal: AddEntrySheet.number(kcal),
                                  proteinG: AddEntrySheet.number(protein),
                                  carbsG: AddEntrySheet.number(carbs),
                                  fatG: AddEntrySheet.number(fat),
                                  portionG: AddEntrySheet.number(portion))
        let ok = dish == nil
            ? await store.createDish(request)
            : await store.updateDish(id: dish!.id, request)
        if ok { dismiss() }
    }
}
