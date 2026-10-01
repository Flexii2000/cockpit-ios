import SwiftUI

/// Die Kategorie fuer den naechsten Baum waehlen - und gleich hier anlegen,
/// umbenennen (Langdruck oder Wischen) und loeschen.
///
/// Antippen waehlt und schliesst; eine neu angelegte Kategorie ist sofort
/// gewaehlt. Ohne Netz bleibt die Auswahl der zuletzt geladenen Liste -
/// angelegt wird nur mit Netz (siehe `FocusSessionsAPI.createCategory`).
struct ForestCategorySheet: View {

    /// Die Wahl ohne Kategorie - so heisst sie auch auf dem Knopf.
    static let none = "Ohne Kategorie"

    let store: ForestStore
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

    private func row(_ category: FocusCategory?) -> some View {
        let selected = store.category?.id == category?.id
        return Button {
            store.category = category
            dismiss()
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
            await run { await store.createCategory(named: name) }
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
