import SwiftUI

/// Gerichte: je eines eine Zutatenliste, die mit einem Tipp komplett auf die
/// Einkaufsliste geht.
struct ShoppingDishesView: View {

    let store: ShoppingStore
    @State private var editing: ShoppingDishTarget?
    /// Das Gericht, dessen Zutaten gerade auf die Liste gegangen sind - der
    /// Knopf zeigt zwei Sekunden lang einen Haken statt des Wagens.
    @State private var justAdded: String?

    var body: some View {
        List {
            ForEach(store.dishes) { dish in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dish.name)
                        Text(ingredientLine(dish))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = .existing(dish) }
                    Spacer(minLength: 0)
                    Button {
                        Task {
                            if await store.addDish(dish) { flash(dish.id) }
                        }
                    } label: {
                        Image(systemName: justAdded == dish.id ? "checkmark.circle.fill" : "cart.badge.plus")
                            .font(.title3)
                            .foregroundStyle(justAdded == dish.id ? Color.green : Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Auf die Liste")
                    .accessibilityIdentifier("addDish-\(dish.id)")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteDish(dish) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
            if store.dishes.isEmpty {
                Text("Noch kein Gericht. Ein Gericht ist eine Zutatenliste, "
                     + "die mit einem Tipp komplett auf die Einkaufsliste geht.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gerichte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neues Gericht")
            }
        }
        .sheet(item: $editing) { target in
            ShoppingDishEditSheet(store: store, dish: target.dish)
        }
    }

    private func ingredientLine(_ dish: ShoppingDish) -> String {
        dish.ingredients.isEmpty ? "keine Zutaten"
            : dish.ingredients.map(\.name).joined(separator: ", ")
    }

    private func flash(_ id: String) {
        justAdded = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if justAdded == id { justAdded = nil }
        }
    }
}

enum ShoppingDishTarget: Identifiable {
    case new
    case existing(ShoppingDish)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let dish): dish.id
        }
    }

    var dish: ShoppingDish? {
        if case .existing(let dish) = self { return dish }
        return nil
    }
}

/// Ein Gericht anlegen oder aendern. Die Zutaten sind Zeilen mit Name und
/// Menge; die leere Zeile am Ende nimmt die naechste - kein Knopf, kein
/// Menue.
struct ShoppingDishEditSheet: View {

    let store: ShoppingStore
    let dish: ShoppingDish?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var rows: [IngredientRow]
    @State private var newIngredient = ""
    @State private var newQuantity = ""
    @State private var isSaving = false
    @FocusState private var typingNew: Bool

    struct IngredientRow: Identifiable {
        let id = UUID()
        var name: String
        var quantity: String
    }

    init(store: ShoppingStore, dish: ShoppingDish?) {
        self.store = store
        self.dish = dish
        _name = State(initialValue: dish?.name ?? "")
        _rows = State(initialValue: (dish?.ingredients ?? []).map {
            IngredientRow(name: $0.name, quantity: $0.quantity ?? "")
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name des Gerichts", text: $name)
                        .accessibilityIdentifier("dishName")
                }
                Section("Zutaten") {
                    ForEach($rows) { $row in
                        HStack {
                            TextField("Zutat", text: $row.name)
                            TextField("Menge", text: $row.quantity)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    HStack {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.tertiary)
                        TextField("Zutat", text: $newIngredient)
                            .focused($typingNew)
                            .submitLabel(.next)
                            .onSubmit { addRow() }
                            .accessibilityIdentifier("newIngredient")
                        TextField("Menge", text: $newQuantity)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { addRow() }
                    }
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
                        .accessibilityIdentifier("saveDish")
                }
            }
        }
    }

    private func addRow() {
        let n = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        rows.append(IngredientRow(name: n, quantity: newQuantity.trimmingCharacters(in: .whitespaces)))
        newIngredient = ""
        newQuantity = ""
        typingNew = true
    }

    private func save() async {
        // Was noch in der leeren Zeile steht, zaehlt mit - sonst ginge die
        // letzte Zutat verloren, weil man Sichern statt Enter getippt hat.
        addRow()
        let ingredients = rows.compactMap { row -> ShoppingIngredient? in
            let n = row.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return nil }
            let q = row.quantity.trimmingCharacters(in: .whitespaces)
            return ShoppingIngredient(name: n, quantity: q.isEmpty ? nil : q)
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        isSaving = true
        defer { isSaving = false }
        let ok: Bool
        if let dish {
            ok = await store.updateDish(dish, name: title, ingredients: ingredients)
        } else {
            ok = await store.createDish(name: title, ingredients: ingredients)
        }
        if ok { dismiss() }
    }
}
