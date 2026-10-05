import SwiftUI

/// Die Kategorie fuer den naechsten Baum waehlen, fuer den wachsenden oder
/// nachtraeglich fuer einen fertigen - und gleich hier anlegen, umbenennen
/// (Langdruck oder Wischen) und loeschen.
///
/// Antippen waehlt und schliesst; eine neu angelegte Kategorie ist sofort
/// gewaehlt. Ohne Netz bleibt die Auswahl der zuletzt geladenen Liste -
/// angelegt wird nur mit Netz (siehe `FocusSessionsAPI.createCategory`),
/// und ein fertiger Baum aendert sich auch nur mit Netz.
struct ForestCategorySheet: View {

    /// Wofuer gewaehlt wird.
    enum Purpose {
        /// Der Knopf ueber „Baum pflanzen".
        case next
        /// Der Baum, der gerade waechst - die Kategorie geht am Ende mit ihm raus.
        case running
        /// Ein fertiger Baum, den der Dienst schon kennt.
        case tree(FocusSession)
    }

    /// Die Wahl ohne Kategorie - so heisst sie auch auf dem Knopf.
    static let none = "Ohne Kategorie"

    let store: ForestStore
    var purpose: Purpose = .next
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var renaming: FocusCategory?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil)
                    ForEach(choices) { category in
                        row(category)
                            .contextMenu {
                                renameButton(category)
                                deleteButton(category)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(category)
                                renameButton(category)
                            }
                    }
                }
                Section {
                    HStack {
                        TextField("Neue Kategorie", text: Binding(
                            get: { newName },
                            set: { newName = String($0.prefix(40)) }))
                            .submitLabel(.done)
                            .onSubmit(create)
                            .accessibilityIdentifier("newCategoryName")
                        if isBusy {
                            ProgressView()
                        } else {
                            Button("Anlegen", action: create)
                                .disabled(ForestStore.categoryName(newName).isEmpty)
                                .accessibilityIdentifier("createCategory")
                        }
                    }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("categoryError")
                    }
                }
            }
            .navigationTitle("Kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Umbenennen", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Sichern") {
                    guard let category = renaming else { return }
                    let name = renameText
                    Task { await run { await store.renameCategory(category, to: name) } }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Nie geladen (kein Netz, nichts im Cache): wenigstens die gemerkte
    /// Kategorie, damit der Haken nicht ins Leere zeigt.
    private var choices: [FocusCategory] {
        store.categories ?? store.category.map { [$0] } ?? []
    }

    /// Was den Haken traegt - beim fertigen Baum der Stand des Dienstes,
    /// nicht der beim Oeffnen des Blatts.
    private var selectedId: String? {
        switch purpose {
        case .next: store.category?.id
        case .running: store.active?.categoryId
        case .tree(let tree): current(tree).categoryId
        }
    }

    private func current(_ tree: FocusSession) -> FocusSession {
        store.allSessions.first { $0.id == tree.id } ?? tree
    }

    /// Liefert die Meldung, wenn der Dienst die Aenderung nicht annimmt.
    private func choose(_ category: FocusCategory?) async -> String? {
        switch purpose {
        case .next:
            store.category = category
            return nil
        case .running:
            store.changeActiveCategory(to: category)
            return nil
        case .tree(let tree):
            return await store.changeCategory(of: current(tree), to: category)
        }
    }

    private func row(_ category: FocusCategory?) -> some View {
        let selected = selectedId == category?.id
        return Button {
            Task {
                await run { await choose(category) }
                if errorMessage == nil { dismiss() }
            }
        } label: {
            HStack {
                Text(category?.name ?? Self.none)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    // Gewaehlt sagt VoiceOver schon ueber `.isSelected`.
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func renameButton(_ category: FocusCategory) -> some View {
        Button {
            renameText = category.name
            renaming = category
        } label: {
            Label("Umbenennen", systemImage: "pencil")
        }
        .tint(.orange)
    }

    private func deleteButton(_ category: FocusCategory) -> some View {
        Button(role: .destructive) {
            Task { await run { await store.deleteCategory(category) } }
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }

    private func create() {
        let name = newName
        guard !ForestStore.categoryName(name).isEmpty, !isBusy else { return }
        Task {
            await run {
                switch await store.createCategory(named: name) {
                case .success(let created): return await choose(created)
                case .failure(let refusal): return refusal.message
                }
            }
            if errorMessage == nil {
                newName = ""
                dismiss()
            }
        }
    }

    /// Eine Aenderung beim Dienst - die Meldung bleibt stehen, bis die
    /// naechste gelingt.
    private func run(_ change: () async -> String?) async {
        isBusy = true
        errorMessage = await change()
        isBusy = false
    }
}
