import SwiftUI

/// Die Einkaufsliste: Offenes oben, Abgehaktes darunter, die Eingabe am
/// Ende. Gerichte und Regeln sind eigene Seiten dahinter - als sichtbare
/// Zeilen in der Liste, nicht in einem Menue.
struct ShoppingTab: View {

    @State private var store = ShoppingStore()
    @State private var newName = ""
    @State private var newQuantity = ""
    @State private var editing: ShoppingItem?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Group {
                if store.board == nil, store.isLoading {
                    LoadingPlaceholder()
                } else if let message = store.errorMessage, store.board == nil {
                    VStack(spacing: 16) {
                        ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                        Button("Erneut versuchen") { Task { await store.load() } }
                    }
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    list
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .shopping) }
            .navigationTitle("Einkaufsliste")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
            }
            .sheet(item: $editing) { item in
                ShoppingItemEditSheet(store: store, item: item)
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                // Der Postausgang ist leer - was dort lag, ist beim Dienst.
                // Jetzt dessen Stand holen, mit echten Kennungen.
                if before > 0, after == 0 { Task { await store.load() } }
            }
        }
    }

    private var list: some View {
        List {
            if let message = store.errorMessage {
                ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(store.openItems) { item in row(item) }
                if store.openItems.isEmpty {
                    Text("Nichts auf der Liste.").foregroundStyle(.secondary)
                }
            } header: {
                Text(store.openItems.count == 1 ? "1 offen" : "\(store.openItems.count) offen")
            }
            if !store.checkedItems.isEmpty {
                Section {
                    ForEach(store.checkedItems) { item in row(item) }
                } header: {
                    HStack {
                        Text("Im Wagen")
                        Spacer()
                        Button("Entfernen") { Task { await store.clearChecked() } }
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
            Section {
                HStack {
                    TextField("Neuer Eintrag", text: $newName)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("newItem")
                    TextField("Menge", text: $newQuantity)
                        .frame(width: 76)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("newQuantity")
                    Button { submit() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addItem")
                }
            }
            Section {
                NavigationLink {
                    ShoppingDishesView(store: store)
                } label: {
                    Label("Gerichte", systemImage: "frying.pan")
                        .badge(store.dishes.count)
                }
                NavigationLink {
                    ShoppingRecurringView(store: store)
                } label: {
                    Label("Regelmäßig", systemImage: "repeat")
                        .badge(store.rules.count)
                }
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Task { await store.toggle(item) }
            } label: {
                Image(systemName: store.pendingIDs.contains(item.id) ? "clock.arrow.circlepath"
                      : item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(item.isLocal)
            .accessibilityIdentifier("toggle-\(item.id)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Das Symbol der Kategorie: die Liste ist danach
                    // sortiert, und das Symbol sagt, wo im Laden man steht.
                    if let category = category(of: item) {
                        Image(systemName: category.symbol)
                            .font(.footnote)
                            .foregroundStyle(item.isChecked ? Color.secondary : Color.accentColor)
                            .frame(width: 18)
                            .accessibilityLabel(category.label)
                    }
                    Text(item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if let quantity = item.quantity, !quantity.isEmpty {
                        Text(quantity).foregroundStyle(.secondary)
                    }
                }
                if let detail = detail(for: item) {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if !item.isLocal { editing = item } }
            Spacer(minLength: 0)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isLocal {
                Button(role: .destructive) {
                    Task { await store.delete(item) }
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    private func category(of item: ShoppingItem) -> ShoppingCategory? {
        guard let key = item.category else { return nil }
        return store.board?.category(key)
    }

    /// „für Lasagne", „von felix", „regelmäßig" - was ueber den Namen hinaus
    /// zaehlt, in einer Zeile.
    private func detail(for item: ShoppingItem) -> String? {
        var parts: [String] = []
        if let note = item.note, !note.isEmpty {
            parts.append(item.dishId != nil ? "für \(note)" : note)
        }
        if item.isChecked, let by = item.checkedBy {
            parts.append("von \(by)")
        } else if item.ruleId != nil {
            parts.append("regelmäßig")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func submit() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let quantity = newQuantity.trimmingCharacters(in: .whitespaces)
        newName = ""
        newQuantity = ""
        // Die Tastatur geht mit dem Eintrag zu - wie beim To-Do.
        typing = false
        Task { await store.add(name: name, quantity: quantity.isEmpty ? nil : quantity) }
    }
}

/// Einen Eintrag berichtigen: Name, Menge, Notiz.
struct ShoppingItemEditSheet: View {

    let store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantity: String
    @State private var note: String
    @State private var category: String

    init(store: ShoppingStore, item: ShoppingItem) {
        self.store = store
        self.item = item
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity ?? "")
        _note = State(initialValue: item.note ?? "")
        _category = State(initialValue: item.category ?? "other")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Menge", text: $quantity)
                TextField("Notiz", text: $note)
                // Die Kategorie kommt vom Dienst; wer sie hier aendert,
                // bringt ihm den Namen bei - beim naechsten Mal sitzt sie.
                Picker("Kategorie", selection: $category) {
                    ForEach(store.board?.categories ?? []) { category in
                        Label(category.label, systemImage: category.symbol).tag(category.key)
                    }
                }
            }
            .navigationTitle("Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let q = quantity.trimmingCharacters(in: .whitespaces)
                        let t = note.trimmingCharacters(in: .whitespaces)
                        // Nur eine bewusst geaenderte Kategorie schicken -
                        // sonst lernte der Dienst seine eigene Vermutung
                        // als Wahrheit.
                        let chosen = category == (item.category ?? "other") ? nil : category
                        Task {
                            if await store.update(item, name: n, quantity: q.isEmpty ? nil : q,
                                                  note: t.isEmpty ? nil : t, category: chosen) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
