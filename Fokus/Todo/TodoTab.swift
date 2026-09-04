import SwiftUI

/// Die Bereiche als Seiten im selben Tab - wischen von Privat zu Uni zu
/// Server. Eine Seite je Bereich statt eines Auswahlfelds oben: drei kurze
/// Namen passen in ein Segment, der vierte nicht mehr, und Bereiche sollen
/// sich anlegen lassen.
struct TodoTab: View {

    @State private var store = TodoStore()
    @State private var page: String?
    @State private var newArea = false
    @State private var newAreaName = ""

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
                    pages
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .todo) }
            .navigationTitle(currentArea?.name ?? "To-Do")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Neuer Bereich …") { newArea = true }
                        if let area = currentArea {
                            Button("„\(area.name)“ umbenennen …") { renameTarget = area }
                            Button("„\(area.name)“ löschen …", role: .destructive) { deleteTarget = area }
                        }
                        Divider()
                        Toggle("Ältere erledigte zeigen", isOn: Binding(
                            get: { store.showsHidden },
                            set: { value in Task { await store.setShowsHidden(value) } }))
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Neuer Bereich", isPresented: $newArea) {
                TextField("Name", text: $newAreaName)
                Button("Anlegen") {
                    let name = newAreaName
                    newAreaName = ""
                    Task {
                        if await store.addArea(name: name) { page = store.areas.last?.id }
                    }
                }
                Button("Abbrechen", role: .cancel) { newAreaName = "" }
            }
            .alert("Bereich umbenennen", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameName)
                Button("Umbenennen") {
                    if let area = renameTarget {
                        let name = renameName
                        Task { await store.renameArea(area, to: name) }
                    }
                    renameTarget = nil
                }
                Button("Abbrechen", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog("Bereich mit allen Aufgaben löschen?",
                                isPresented: Binding(
                                    get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let area = deleteTarget { Task { await store.deleteArea(area) } }
                    deleteTarget = nil
                }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
            .onChange(of: renameTarget?.id) { _, _ in renameName = renameTarget?.name ?? "" }
        }
    }

    @State private var renameTarget: TodoArea?
    @State private var renameName = ""
    @State private var deleteTarget: TodoArea?

    private var currentArea: TodoArea? {
        store.areas.first { $0.id == page } ?? store.areas.first
    }

    private var pages: some View {
        TabView(selection: $page) {
            ForEach(store.areas) { area in
                AreaPage(area: area, store: store)
                    .tag(Optional(area.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: store.areas.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear {
            guard page == nil else { return }
            #if DEBUG
            // COCKPIT_TODO_AREA=Uni oeffnet eine bestimmte Seite - fuer
            // Aufnahmen; wischen kann der Simulator nicht.
            if let wanted = ProcessInfo.processInfo.environment["COCKPIT_TODO_AREA"],
               let area = store.areas.first(where: { $0.name == wanted }) {
                page = area.id
                return
            }
            #endif
            page = store.areas.first?.id
        }
    }
}

/// Eine Seite: die Aufgaben eines Bereichs, mit Eingabe am Ende.
private struct AreaPage: View {

    let area: TodoArea
    let store: TodoStore

    @State private var newTitle = ""
    @State private var subParent: TodoItem?
    @State private var subTitle = ""
    @State private var detail: TodoItem?

    var body: some View {
        List {
            if let message = store.errorMessage {
                ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(area.todos) { todo in
                    row(todo, indent: false)
                    ForEach(todo.children) { child in
                        row(child, indent: true)
                    }
                }
                if area.todos.isEmpty {
                    Text("Nichts offen.").foregroundStyle(.secondary)
                }
            } header: {
                Text(area.openCount == 1 ? "1 offen" : "\(area.openCount) offen")
            } footer: {
                if area.hiddenDoneCount > 0, !store.showsHidden {
                    Text("\(area.hiddenDoneCount) ältere erledigte sind ausgeblendet – im Menü einblenden.")
                }
            }
            Section {
                HStack {
                    TextField("Neue Aufgabe", text: $newTitle)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("newTodo")
                    Button { submit() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addTodo")
                }
            }
        }
        .sheet(item: $detail) { todo in
            TodoDetailSheet(todo: todo, store: store)
        }
        .alert("Unteraufgabe", isPresented: Binding(
            get: { subParent != nil },
            set: { if !$0 { subParent = nil } })) {
            TextField("Text", text: $subTitle)
            Button("Anlegen") {
                if let parent = subParent {
                    let title = subTitle
                    subTitle = ""
                    Task { await store.add(title: title, to: area, under: parent) }
                }
                subParent = nil
            }
            Button("Abbrechen", role: .cancel) { subParent = nil; subTitle = "" }
        } message: {
            if let parent = subParent { Text("zu „\(parent.title)“") }
        }
    }

    private func submit() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newTitle = ""
        Task { await store.add(title: title, to: area) }
    }

    private func row(_ todo: TodoItem, indent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Task { await store.toggle(todo) }
            } label: {
                Image(systemName: store.pendingIDs.contains(todo.id) ? "clock.arrow.circlepath"
                      : todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle-\(todo.id)")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                if todo.dueAt != nil || !todo.reminders.isEmpty {
                    HStack(spacing: 8) {
                        if let dueAt = todo.dueAt {
                            Text("bis \(dueAt.short)")
                                .foregroundStyle(todo.isOverdue ? Color.red : Color.secondary)
                                .fontWeight(todo.isOverdue ? .semibold : .regular)
                        }
                        if !todo.reminders.isEmpty {
                            // Kein Label: das setzt Symbol und Zahl weit
                            // auseinander, als gehoerten sie nicht zusammen.
                            HStack(spacing: 3) {
                                Image(systemName: "bell")
                                Text("\(todo.reminders.count)")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { detail = todo }
            Spacer(minLength: 0)
        }
        .padding(.leading, indent ? 28 : 0)
        .swipeActions(edge: .leading) {
            if !indent, !todo.isDone {
                Button { subParent = todo; subTitle = "" } label: {
                    Label("Unteraufgabe", systemImage: "arrow.turn.down.right")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await store.delete(todo) }
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}


/// Faelligkeit und Erinnerungen einer Aufgabe.
struct TodoDetailSheet: View {

    let todo: TodoItem
    let store: TodoStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var reminderAt = Date().addingTimeInterval(3600)

    init(todo: TodoItem, store: TodoStore) {
        self.todo = todo
        self.store = store
        _title = State(initialValue: todo.title)
        _hasDue = State(initialValue: todo.dueAt != nil)
        _due = State(initialValue: todo.dueAt?.startOfDay() ?? Date())
    }

    /// Der Stand aus dem Brett, nicht die Kopie vom Oeffnen: nach einer neuen
    /// Erinnerung soll sie hier auch stehen.
    private var live: TodoItem { store.current(todo) ?? todo }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Aufgabe", text: $title)
                    Toggle("Fällig am", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Datum", selection: $due, displayedComponents: .date)
                    }
                } footer: {
                    Text("Überfällig wird rot - mehr passiert nicht.")
                }
                Section {
                    ForEach(live.reminders) { reminder in
                        HStack {
                            Text(reminder.at.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            if reminder.sentAt != nil {
                                Text("geschickt").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await store.deleteReminder(reminder, from: live) }
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                    DatePicker("Neu", selection: $reminderAt, in: Date()...)
                    Button("Erinnerung anlegen") {
                        Task { await store.addReminder(to: live, at: reminderAt) }
                    }
                } header: {
                    Text("Erinnerungen")
                } footer: {
                    Text("Beliebig viele. Der Dienst schickt sie als Benachrichtigung - "
                         + "auch wenn die App zu ist, und nur solange die Aufgabe offen ist.")
                }
            }
            .navigationTitle("Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            let day = hasDue ? CalendarDate(date: due) : nil
                            if await store.update(live, title: title.trimmingCharacters(in: .whitespaces),
                                                  dueAt: day) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
