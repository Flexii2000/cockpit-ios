import SwiftUI

/// Die Verhaltensweisen des Logbooks: anlegen (ja/nein oder mit Einheit),
/// umbenennen, archivieren, loeschen.
///
/// Nur mit Netz - die Kennung vergibt der Dienst, und Loeschen nimmt alle
/// Werte mit; nichts davon gehoert in einen Postausgang.
struct LogbookBehaviorsSheet: View {

    let store: LogbookStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var withUnit = false
    @State private var unit = ""
    @State private var isWorking = false
    @State private var renaming: Behavior?
    @State private var newName = ""
    @State private var deleting: Behavior?
    @FocusState private var nameFocused: Bool

    /// Was der Dienst annimmt: Name 1 bis 40 Zeichen, Einheit bis 16.
    private var canAdd: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanUnit = unit.trimmingCharacters(in: .whitespaces)
        guard (1...40).contains(cleanName.count), !isWorking else { return false }
        return !withUnit || (1...16).contains(cleanUnit.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Neu") {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                    Picker("Art", selection: $withUnit) {
                        Text("Ja/Nein").tag(false)
                        Text("Mit Einheit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if withUnit {
                        TextField("Einheit", text: $unit)
                    }
                    Button("Anlegen") { Task { await add() } }
                        .disabled(!canAdd)
                }

                if let overview = store.overview {
                    if !overview.active.isEmpty {
                        Section("Aktiv") {
                            ForEach(overview.active) { row($0) }
                        }
                    }
                    if !overview.archived.isEmpty {
                        Section("Archiviert") {
                            ForEach(overview.archived) { row($0) }
                        }
                    }
                }

                if let error = store.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Verhalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Umbenennen", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Abbrechen", role: .cancel) { renaming = nil }
                Button("Sichern") {
                    if let behavior = renaming {
                        Task { await work { await store.rename(behavior, to: newName) } }
                    }
                    renaming = nil
                }
            }
            .confirmationDialog(deleting.map { "„\($0.name)“ löschen?" } ?? "",
                                isPresented: Binding(get: { deleting != nil },
                                                     set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let behavior = deleting {
                        Task { await work { await store.delete(behavior) } }
                    }
                    deleting = nil
                }
            } message: {
                Text("Die Werte an allen Tagen gehen mit.")
            }
            .onAppear {
                // Ohne Verhaltensweise ist das Anlegen der einzige Grund, hier zu sein.
                if store.overview?.behaviors.isEmpty ?? true { nameFocused = true }
            }
        }
    }

    /// Antippen benennt um; nach links wischen loescht, nach rechts
    /// archiviert bzw. holt zurueck - dasselbe im Kontextmenue.
    private func row(_ behavior: Behavior) -> some View {
        HStack {
            Text(behavior.name)
                .foregroundStyle(behavior.archived ? .secondary : .primary)
            Spacer()
            if let unit = behavior.unit {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { startRenaming(behavior) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = behavior } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { Task { await work { await store.setArchived(behavior, !behavior.archived) } } } label: {
                Label(behavior.archived ? "Zurückholen" : "Archivieren",
                      systemImage: behavior.archived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button("Umbenennen") { startRenaming(behavior) }
            Button(behavior.archived ? "Zurückholen" : "Archivieren") {
                Task { await work { await store.setArchived(behavior, !behavior.archived) } }
            }
            Button("Löschen", role: .destructive) { deleting = behavior }
        }
    }

    private func startRenaming(_ behavior: Behavior) {
        newName = behavior.name
        renaming = behavior
    }

    private func add() async {
        let added = await work {
            await store.addBehavior(name: name, unit: withUnit ? unit : nil)
        }
        if added {
            name = ""
            unit = ""
            withUnit = false
        }
    }

    /// Haelt die Knoepfe still, solange der Dienst arbeitet.
    @discardableResult
    private func work(_ action: () async -> Bool) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        return await action()
    }
}
