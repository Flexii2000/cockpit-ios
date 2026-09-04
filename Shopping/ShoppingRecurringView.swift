import SwiftUI

/// Was von selbst wiederkommt: Klopapier alle 14 Tage. Der Dienst setzt es
/// auf die Liste, sobald der Tag da ist, und rechnet ab dem Abhaken neu.
struct ShoppingRecurringView: View {

    let store: ShoppingStore
    @State private var editing: ShoppingRuleTarget?

    var body: some View {
        List {
            ForEach(store.rules) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(rule.name)
                        if let quantity = rule.quantity, !quantity.isEmpty {
                            Text(quantity).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(Self.cadence(rule.everyDays)) · nächstes Mal \(Self.nextLabel(rule.nextAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = .existing(rule) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteRule(rule) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
            if store.rules.isEmpty {
                Text("Noch keine Regel. Eine Regel setzt etwas von selbst auf die "
                     + "Liste - Klopapier alle 14 Tage.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Regelmäßig")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neue Regel")
            }
        }
        .sheet(item: $editing) { target in
            ShoppingRuleEditSheet(store: store, rule: target.rule)
        }
    }

    static func cadence(_ days: Int) -> String {
        switch days {
        case 1: "täglich"
        case 7: "wöchentlich"
        default: "alle \(days) Tage"
        }
    }

    /// „heute" auch fuer Ueberfaelliges: der Dienst setzt es beim naechsten
    /// Lauf auf die Liste, oder es liegt schon offen dort.
    static func nextLabel(_ date: CalendarDate) -> String {
        let days = date.daysFromToday()
        switch days {
        case ...0: return "heute"
        case 1: return "morgen"
        case 2...7: return "in \(days) Tagen"
        default: return date.short
        }
    }
}

enum ShoppingRuleTarget: Identifiable {
    case new
    case existing(ShoppingRule)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let rule): rule.id
        }
    }

    var rule: ShoppingRule? {
        if case .existing(let rule) = self { return rule }
        return nil
    }
}

struct ShoppingRuleEditSheet: View {

    let store: ShoppingStore
    let rule: ShoppingRule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantity: String
    @State private var unit: ShoppingQuantity.Unit
    @State private var everyDays: Int
    @State private var nextAt: Date
    @State private var isSaving = false

    init(store: ShoppingStore, rule: ShoppingRule?) {
        self.store = store
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        let parsed = ShoppingQuantity.parse(rule?.quantity)
        _quantity = State(initialValue: parsed?.amount ?? rule?.quantity ?? "")
        _unit = State(initialValue: parsed?.unit ?? .piece)
        _everyDays = State(initialValue: rule?.everyDays ?? 14)
        _nextAt = State(initialValue: rule?.nextAt.startOfDay() ?? CalendarDate.today().startOfDay())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("ruleName")
                    LabeledContent("Menge") {
                        QuantityField(amount: $quantity, unit: $unit)
                    }
                }
                Section {
                    Stepper(value: $everyDays, in: 1...365) {
                        Text(ShoppingRecurringView.cadence(everyDays))
                    }
                    DatePicker("Nächstes Mal", selection: $nextAt, displayedComponents: .date)
                } footer: {
                    Text("Ab dem Abhaken zählt der Rhythmus neu - wer früher kauft, "
                         + "bekommt es entsprechend früher wieder.")
                }
            }
            .navigationTitle(rule == nil ? "Neue Regel" : "Regel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("saveRule")
                }
            }
        }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        let q = ShoppingQuantity.compose(quantity, unit: unit)
        let day = CalendarDate(date: nextAt)
        isSaving = true
        defer { isSaving = false }
        let ok: Bool
        if let rule {
            ok = await store.updateRule(rule, name: n, quantity: q,
                                        everyDays: everyDays, nextAt: day)
        } else {
            ok = await store.createRule(name: n, quantity: q,
                                        everyDays: everyDays, nextAt: day)
        }
        if ok { dismiss() }
    }
}
