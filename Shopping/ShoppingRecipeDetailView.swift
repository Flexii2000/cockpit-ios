import SwiftUI

/// Ein Rezept: fuer wie viele Portionen, was davon auf die Liste soll, die Schritte,
/// die Naehrwerte - und von hier aus auf die Liste oder ans Kochen.
///
/// Die Mengen rechnet die App selbst um (`ShoppingQuantity.scale`, dieselbe Tabelle
/// wie beim Dienst): der Portionswaehler soll auch im Laden ohne Netz gehen, und
/// „Auf die Liste“ zeigt die Eintraege sofort mit genau diesen Mengen.
struct ShoppingRecipeDetailView: View {

    let store: ShoppingStore
    let dishId: String
    @Environment(\.dismiss) private var dismiss

    /// Fuer so viele Portionen; `nil` = wie das Rezept.
    @State private var chosenPortions: Int?
    /// Zutaten, die nicht mit auf die Liste sollen - nach Position im Rezept.
    /// Vorrat ist von Anfang an abgewaehlt.
    @State private var deselected: Set<Int> = []
    @State private var seeded = false
    @State private var isEditing = false
    /// Zwei Sekunden lang ein Haken am Knopf, nachdem die Zutaten auf die Liste gingen.
    @State private var justAdded = false

    private var dish: ShoppingDish? { store.dishes.first { $0.id == dishId } }

    var body: some View {
        Group {
            if let dish {
                content(dish)
            } else {
                // Geloescht (von hier oder vom anderen Handy): zurueck zur Liste.
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    private func content(_ dish: ShoppingDish) -> some View {
        let portions = chosenPortions ?? dish.basePortions
        let ingredients = dish.ingredients(for: portions)
        return List {
            if dish.basePortions != nil || dish.minutes != nil {
                Section {
                    if let base = dish.basePortions {
                        Stepper(value: Binding(get: { chosenPortions ?? base },
                                               set: { chosenPortions = $0 }), in: 1...99) {
                            Text(ShoppingRecipeFormat.portions(portions ?? base))
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier("portions")
                    }
                    if let minutes = dish.minutes, minutes > 0 {
                        LabeledContent("Zeit", value: "\(minutes) Min.")
                    }
                }
            }
            if !ingredients.isEmpty {
                Section("Zutaten") {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                        ingredientRow(ingredient, index: index)
                    }
                }
            }
            if !dish.stepList.isEmpty {
                Section("Schritte") {
                    ForEach(Array(dish.stepList.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(step)
                        }
                    }
                }
            }
            if let nutrition = dish.nutrition, nutrition.isComplete {
                Section {
                    ShoppingNutritionRow(nutrition: nutrition)
                }
            }
        }
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isEditing = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Bearbeiten")
                    .accessibilityIdentifier("editRecipe")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions(dish, portions: portions) }
        .sheet(isPresented: $isEditing) {
            ShoppingRecipeEditSheet(store: store, dish: dish)
        }
        .onAppear { seed(dish) }
        .onChange(of: dish.ingredients) { _, _ in
            // Nach dem Bearbeiten stimmen die Positionen nicht mehr: neu vorbelegen.
            seeded = false
            seed(dish)
        }
    }

    private func ingredientRow(_ ingredient: ShoppingScaledIngredient, index: Int) -> some View {
        let isOn = !deselected.contains(index)
        return Button {
            if isOn { deselected.insert(index) } else { deselected.remove(index) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(ingredient.name)
                    .foregroundStyle(isOn ? .primary : .secondary)
                Spacer(minLength: 8)
                if let quantity = ingredient.quantity, !quantity.isEmpty {
                    // Was sich nicht umrechnen liess („eine Handvoll“), steht blasser
                    // und schraeg da: es gilt fuer die Portionen des Rezepts.
                    Text(quantity)
                        .foregroundStyle(ingredient.scaled ? .secondary : .tertiary)
                        .italic(!ingredient.scaled)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ingredient-\(index)")
        .accessibilityValue(isOn ? "kommt mit" : "bleibt weg")
    }

    private func actions(_ dish: ShoppingDish, portions: Int?) -> some View {
        HStack(spacing: 12) {
            Button {
                let skipped = dish.ingredients.enumerated()
                    .filter { deselected.contains($0.offset) }
                    .map(\.element.name)
                // Steht sofort auf der Liste, auch ohne Netz.
                if store.addRecipe(dish, portions: portions, skipping: skipped) { flash() }
            } label: {
                Label("Auf die Liste", systemImage: justAdded ? "checkmark" : "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(deselected.count >= dish.ingredients.count)
            .accessibilityIdentifier("addRecipe")

            NavigationLink(value: ShoppingRoute.cook(id: dish.id, portions: portions)) {
                Label("Kochen", systemImage: "frying.pan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("cook")
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func seed(_ dish: ShoppingDish) {
        guard !seeded else { return }
        seeded = true
        deselected = Set(dish.ingredients.enumerated().filter(\.element.isPantry).map(\.offset))
    }

    private func flash() {
        justAdded = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justAdded = false
        }
    }
}
