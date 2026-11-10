import SwiftUI

/// Der Rezept-Chat: sagen, worauf man Lust hat, und einen Vorschlag bekommen, den
/// man ansehen und als Rezept speichern kann. Schlichte Blasen - das Gespraech
/// liegt beim Dienst, hier wird nur gezeigt.
struct ShoppingChatView: View {

    let store: ShoppingStore
    let chat: ShoppingChatStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var text = ""
    /// Die Antwort, deren Entwurf gerade angesehen wird.
    @State private var preview: ShoppingChatMessage?
    /// Die Antwort, deren Entwurf gerade gespeichert wird.
    @State private var saving: String?
    @FocusState private var typing: Bool

    private static let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(chat.rows) { row in
                        view(for: row)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.rows) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { input }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neu") { Task { await chat.reset() } }
                    .disabled(chat.isEmpty)
                    .accessibilityIdentifier("newChat")
            }
        }
        .sheet(item: $preview) { message in
            if let draft = message.draft {
                ShoppingDraftSheet(draft: draft, isSaved: message.savedDishId != nil) {
                    await save(message)
                }
            }
        }
        .task { await chat.load() }
        .onDisappear { chat.pause() }
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund: die Antwort ist vielleicht laengst da.
            if phase == .active { Task { await chat.load() } } else { chat.pause() }
        }
    }

    // MARK: - Zeilen

    @ViewBuilder
    private func view(for row: ShoppingChatRow) -> some View {
        switch row {
        case .message(let message):
            if message.isMine {
                bubble(message.text, mine: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !message.text.isEmpty { bubble(message.text, mine: false) }
                    if let draft = message.draft { card(draft, message: message) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .sending(let pending):
            bubble(pending.text, mine: true).opacity(0.6)
        case .typing:
            ProgressView()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Antwort entsteht")
                .accessibilityIdentifier("chatTyping")
        case .failed(let message):
            HStack(spacing: 10) {
                Text(message ?? "Keine Antwort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Erneut senden") { Task { await chat.retry() } }
                    .font(.footnote.weight(.medium))
                    .accessibilityIdentifier("retryChat")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(mine ? Color.white : Color.primary)
            .background(mine ? Color.accentColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .textSelection(.enabled)
    }

    /// Der Vorschlag an einer Antwort: ansehen, speichern - danach das Rezept oeffnen.
    private func card(_ draft: ShoppingRecipeDraft, message: ShoppingChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.name).font(.headline)
            if let meta = ShoppingRecipeFormat.meta(portions: draft.portions, minutes: draft.minutes,
                                                    kcal: draft.nutrition?.kcal) {
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let dishId = message.savedDishId, store.dishes.contains(where: { $0.id == dishId }) {
                    NavigationLink(value: ShoppingRoute.recipe(id: dishId)) {
                        Label("Rezept", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("openSavedRecipe")
                } else {
                    Button("Ansehen") {
                        typing = false
                        preview = message
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("viewDraft")
                    Button("Speichern") { Task { await save(message) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving != nil || message.savedDishId != nil)
                        .accessibilityIdentifier("saveDraft")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: - Eingabe

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Nachricht", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("chatField")
            Button {
                let message = text
                text = ""
                Task { await chat.send(message) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isBusy)
            .accessibilityLabel("Senden")
            .accessibilityIdentifier("sendChat")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Speichert den Entwurf als Rezept; das Brett kommt als Antwort, und das
    /// Gespraech sagt danach, welches Rezept daraus wurde.
    @discardableResult
    private func save(_ message: ShoppingChatMessage) async -> Bool {
        guard saving == nil else { return false }
        saving = message.id
        defer { saving = nil }
        guard await store.saveDraft(messageId: message.id) else { return false }
        await chat.refresh()
        return true
    }
}

/// Ein Vorschlag aus dem Chat zum Ansehen, bevor er ein Rezept wird: dieselben
/// Abschnitte wie im Rezept, nur ohne Auswahl.
struct ShoppingDraftSheet: View {

    let draft: ShoppingRecipeDraft
    let isSaved: Bool
    /// Speichert und sagt, ob es ging - dann geht das Blatt zu.
    let save: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                // Der Name als Zeile, nicht als Titel: zwischen „Schließen“ und
                // „Speichern“ bliebe von ihm nur „Ofenpasta mit…“.
                Section {
                    Text(draft.name).font(.title3.weight(.semibold))
                    if let meta = ShoppingRecipeFormat.meta(portions: draft.portions, minutes: draft.minutes) {
                        Text(meta).foregroundStyle(.secondary)
                    }
                }
                if !draft.ingredients.isEmpty {
                    Section("Zutaten") {
                        ForEach(Array(draft.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            HStack {
                                Text(ingredient.name)
                                if ingredient.isPantry {
                                    Image(systemName: "house")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Vorrat")
                                }
                                Spacer(minLength: 8)
                                if let quantity = ingredient.quantity, !quantity.isEmpty {
                                    Text(quantity).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                if !draft.steps.isEmpty {
                    Section("Schritte") {
                        ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                                Text(step)
                            }
                        }
                    }
                }
                if let nutrition = draft.nutrition, nutrition.isComplete {
                    Section { ShoppingNutritionRow(nutrition: nutrition) }
                }
            }
            .navigationTitle("Vorschlag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if !isSaved {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            Task {
                                isSaving = true
                                defer { isSaving = false }
                                if await save() { dismiss() }
                            }
                        }
                        .disabled(isSaving)
                        .accessibilityIdentifier("saveDraftSheet")
                    }
                }
            }
        }
    }
}
