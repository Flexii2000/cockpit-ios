import SwiftUI

/// Wohin es in der Einkaufsliste hinter der Liste geht. Als Werte im Stapel, damit
/// eine Seite die naechste oeffnen kann, ohne sie zu kennen - der Chat das
/// gespeicherte Rezept, das Rezept die Kochansicht.
enum ShoppingRoute: Hashable {
    case recipes
    case recurring
    case recipe(id: String)
    /// `portions`: fuer so viele wird gekocht; `nil` = wie das Rezept.
    case cook(id: String, portions: Int?)
    case chat
}

/// Rezepte: Zutatenlisten, die als Ganzes auf die Einkaufsliste gehen - seit
/// November 2026 auf Wunsch mit Portionen, Schritten und Naehrwerten, und der Chat
/// schlaegt welche vor. Ein Gericht von frueher ist ein Rezept ohne das alles und
/// behaelt seinen einen Tipp „Auf die Liste“.
struct ShoppingRecipesView: View {

    let store: ShoppingStore
    let chat: ShoppingChatStore
    @State private var isCreating = false
    /// Das Gericht, dessen Zutaten gerade auf die Liste gegangen sind - der
    /// Knopf zeigt zwei Sekunden lang einen Haken statt des Wagens.
    @State private var justAdded: String?

    var body: some View {
        List {
            ForEach(store.dishes) { dish in
                NavigationLink(value: ShoppingRoute.recipe(id: dish.id)) {
                    row(dish)
                }
                .accessibilityIdentifier("recipe-\(dish.id)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteDish(dish) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Rezepte")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Nur wer freigeschaltet ist und einen eingerichteten Agenten hat,
                // sieht den Chat - sonst gibt es ihn schlicht nicht.
                if chat.isAvailable {
                    NavigationLink(value: ShoppingRoute.chat) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel("Chat")
                    .accessibilityIdentifier("openChat")
                }
                Button { isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neues Rezept")
                    .accessibilityIdentifier("newRecipe")
            }
        }
        .sheet(isPresented: $isCreating) {
            ShoppingRecipeEditSheet(store: store, dish: nil)
        }
        .task { await chat.load() }
    }

    private func row(_ dish: ShoppingDish) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.name)
                if let line = ShoppingRecipeFormat.listLine(dish) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Ein Gericht ohne Portionen und Vorrat: da gibt es nichts zu waehlen,
            // also weiter mit einem Tipp. Alles andere entscheidet man im Rezept.
            if dish.isPlain, !dish.ingredients.isEmpty {
                Button {
                    // Steht sofort auf der Liste, auch ohne Netz.
                    store.addDish(dish)
                    flash(dish.id)
                } label: {
                    Image(systemName: justAdded == dish.id ? "checkmark.circle.fill" : "cart.badge.plus")
                        .font(.title3)
                        .foregroundStyle(justAdded == dish.id ? Color.green : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Auf die Liste")
                .accessibilityIdentifier("addDish-\(dish.id)")
            }
        }
    }

    private func flash(_ id: String) {
        justAdded = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if justAdded == id { justAdded = nil }
        }
    }
}

/// Wie ein Rezept in Zeilen und Kacheln steht - an einer Stelle, damit Liste,
/// Rezept, Entwurf und Kochansicht dasselbe sagen.
enum ShoppingRecipeFormat {

    private static let german = Locale(identifier: "de_DE")

    /// „2 Portionen · 35 Min. · 860 kcal“ - was davon da ist; ohne alles `nil`.
    static func meta(portions: Int?, minutes: Int?, kcal: Double? = nil) -> String? {
        var parts: [String] = []
        if let portions, portions > 0 { parts.append(Self.portions(portions)) }
        if let minutes, minutes > 0 { parts.append("\(minutes) Min.") }
        if let kcal { parts.append("\(number(kcal)) kcal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Die zweite Zeile in der Liste: beim Rezept Portionen und Zeit, beim Gericht
    /// von frueher wie bisher die Zutaten.
    static func listLine(_ dish: ShoppingDish) -> String? {
        if let meta = meta(portions: dish.basePortions, minutes: dish.minutes) { return meta }
        return dish.ingredients.isEmpty ? nil : dish.ingredients.map(\.name).joined(separator: ", ")
    }

    static func portions(_ count: Int) -> String {
        count == 1 ? "1 Portion" : "\(count) Portionen"
    }

    /// Deutsch, hoechstens eine Nachkommastelle: „860“, „7,5“, „1.250“.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(german))
    }

    /// Fuer ein Eingabefeld: ohne Tausenderpunkt, mit Komma, leer ohne Wert.
    static func field(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }

    /// Was in einem Zahlenfeld steht, als Zahl - mit Komma oder Punkt; leer ist `nil`.
    static func value(_ field: String) -> Double? {
        let trimmed = field.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    /// Der Name hinter einem Token, wie man ihn liest: „felix“ wird „Felix“.
    static func person(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Die Naehrwerte je Portion als vier Zahlen nebeneinander - im Rezept und im
/// Entwurf aus dem Chat.
struct ShoppingNutritionRow: View {

    let nutrition: ShoppingNutrition

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            cell(nutrition.kcal, unit: "kcal", label: "je Portion")
            cell(nutrition.proteinG, unit: "g", label: "Eiweiß")
            cell(nutrition.carbsG, unit: "g", label: "Kohlenhydrate")
            cell(nutrition.fatG, unit: "g", label: "Fett")
        }
        .accessibilityElement(children: .combine)
    }

    private func cell(_ value: Double?, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\(ShoppingRecipeFormat.number($0)) \(unit)" } ?? "–")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
