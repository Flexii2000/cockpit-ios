import SwiftUI
import UIKit

/// Kochen: Zutaten und Schritte zum Abhaken, der Bildschirm bleibt an.
///
/// Beim Oeffnen legt der Dienst das Rezept als Gericht in den Kalorienzaehler -
/// bei allen, die Healthy haben -, damit man es dort gleich eintragen kann. Das
/// braucht Netz; kochen kann man auch ohne: die Ansicht oeffnet aus dem Stand, den
/// die App hat, und zeigt nur, dass Healthy es noch nicht weiss.
struct ShoppingCookView: View {

    let store: ShoppingStore
    let dishId: String
    /// Fuer so viele Portionen; `nil` = wie das Rezept.
    let portions: Int?
    @Environment(\.scenePhase) private var scenePhase

    @State private var healthy: Healthy = .asking
    @State private var usedIngredients: Set<Int> = []
    @State private var doneSteps: Set<Int> = []

    /// Was der Kalorienzaehler zum Gericht sagt.
    private enum Healthy: Equatable {
        case asking
        case answered(ShoppingCookResult)
        /// Keine Antwort - kein Netz, oder der Dienst kam nicht durch.
        case unreachable
    }

    private var dish: ShoppingDish? { store.dishes.first { $0.id == dishId } }

    var body: some View {
        Group {
            if let dish {
                content(dish)
            } else {
                Color.clear
            }
        }
        // Mit Mehl an den Fingern entsperrt niemand das Handy. Nur solange die
        // Ansicht vorn ist - danach gilt wieder die Einstellung des Geraets.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .task { await cook() }
    }

    private func content(_ dish: ShoppingDish) -> some View {
        let count = portions ?? dish.basePortions
        let ingredients = dish.ingredients(for: count)
        return List {
            Section {
                if let meta = ShoppingRecipeFormat.meta(portions: count, minutes: dish.minutes) {
                    Text(meta).foregroundStyle(.secondary)
                }
                marks
            }
            if !ingredients.isEmpty {
                Section("Zutaten") {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                        tickRow(isDone: usedIngredients.contains(index), identifier: "cookIngredient-\(index)") {
                            toggle(index, in: &usedIngredients)
                        } label: { done in
                            HStack {
                                Text(ingredient.name).strikethrough(done)
                                Spacer(minLength: 8)
                                if let quantity = ingredient.quantity, !quantity.isEmpty {
                                    Text(quantity)
                                        .foregroundStyle(ingredient.scaled ? .secondary : .tertiary)
                                        .italic(!ingredient.scaled)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            if !dish.stepList.isEmpty {
                Section("Schritte") {
                    ForEach(Array(dish.stepList.enumerated()), id: \.offset) { index, step in
                        tickRow(isDone: doneSteps.contains(index), identifier: "cookStep-\(index)") {
                            toggle(index, in: &doneSteps)
                        } label: { done in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).").monospacedDigit()
                                Text(step).strikethrough(done)
                            }
                        }
                    }
                }
            }
        }
        .font(.title3)
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Je Person, ob das Gericht in ihrem Kalorienzaehler steht. Ohne Naehrwerte am
    /// Rezept (oder ohne Verbindung der Dienste) gibt es dort nichts - dann steht
    /// hier auch nichts.
    @ViewBuilder
    private var marks: some View {
        switch healthy {
        case .asking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Healthy").foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .answered(let result):
            if result.reason == nil, !result.healthy.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    ForEach(result.healthy) { person in
                        mark(ShoppingRecipeFormat.person(person.person), done: person.isDone)
                            .accessibilityValue(person.isDone ? "in Healthy" : (person.message ?? "nicht in Healthy"))
                    }
                }
                .accessibilityIdentifier("healthyMarks")
                // Bei einer Person nicht geklappt: derselbe Aufruf noch einmal schadet
                // den anderen nicht (dort „unveraendert“).
                if result.healthy.contains(where: { !$0.isDone }) { retryButton }
            }
        case .unreachable:
            HStack(spacing: 12) {
                mark("Healthy", done: false)
                retryButton
            }
        }
    }

    /// Bild und Text von Hand nebeneinander statt als `Label`: in einer Liste
    /// bekommt ein `Label` die Spalten der Listenzeile, und im Umbruch (`FlowLayout`)
    /// blieb davon nur das Symbol in einer hohen Kapsel.
    private func mark(_ name: String, done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark" : "xmark")
                .font(.caption.weight(.bold))
            Text(name)
        }
        .font(.subheadline.weight(.medium))
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(done ? Color.green : Color.red)
        .background((done ? Color.green : Color.red).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var retryButton: some View {
        Button {
            Task { await cook() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
        .accessibilityLabel("Erneut versuchen")
        .accessibilityIdentifier("retryHealthy")
    }

    private func tickRow<Label: View>(isDone: Bool, identifier: String, action: @escaping () -> Void,
                                      @ViewBuilder label: (Bool) -> Label) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
                // Ueber die ganze Breite: sonst bricht ein langer Schritt nach der
                // Breite um, die er fuer sich allein gern haette.
                label(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isDone ? "erledigt" : "")
    }

    private func toggle(_ index: Int, in set: inout Set<Int>) {
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
    }

    private func cook() async {
        guard let dish else { return }
        // Ohne Naehrwerte und Gewicht je Portion legt der Dienst nichts an - dann
        // gibt es auch nichts zu fragen, und ohne Netz stuende hier sonst ein
        // Fehler fuer etwas, das nie geplant war.
        guard dish.nutrition?.isComplete == true, (dish.gramsPerPortion ?? 0) > 0 else {
            healthy = .answered(ShoppingCookResult(dishId: dish.id, reason: "no-nutrition"))
            return
        }
        healthy = .asking
        if let result = await store.cook(dish) {
            healthy = .answered(result)
        } else {
            healthy = .unreachable
        }
    }
}
