import SwiftUI

/// Die Bereiche als Seiten im selben Tab - wischen von Privat zu Uni zu
/// Server. Eine Seite je Bereich statt eines Auswahlfelds oben: drei kurze
/// Namen passen in ein Segment, der vierte nicht mehr, und Bereiche sollen
/// sich anlegen lassen.
///
/// Daneben „Heute" (seit 26.10.): ein Umschalter in der Titelzeile, auf einer
/// Ebene mit „To-Do" - so wollte es Felix, statt einer eigenen Zeile darunter.
/// Der Name des Bereichs steht dafuer ueber der Liste.
struct TodoTab: View {

    enum Mode: String {
        case lists, today
    }

    @State private var store = TodoStore()
    /// Gemerkt: wer morgens in „Heute" arbeitet, will nach dem Wechsel in eine
    /// andere App nicht wieder bei den Listen landen.
    @AppStorage("todo.mode") private var mode: Mode = .lists
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
                } else if mode == .today {
                    TodayPage(store: store)
                } else {
                    pages
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .todo) }
            .navigationTitle(mode == .today ? "Heute" : currentArea?.name ?? "To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $mode) {
                        Text("To-Do").tag(Mode.lists)
                        Text("Heute").tag(Mode.today)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("todoMode")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if mode == .lists {
                            Button("Neuer Bereich …") { newArea = true }
                            if let area = currentArea {
                                Button("„\(area.name)“ umbenennen …") { renameTarget = area }
                                Button("„\(area.name)“ löschen …", role: .destructive) { deleteTarget = area }
                            }
                            Divider()
                        }
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
                        if await store.addArea(name: name) {
                            page = store.areas.last?.id
                        } else {
                            // Nicht angelegt (kein Netz, Name doppelt): der Name steht
                            // wieder da, die Meldung oben sagt warum.
                            newAreaName = name
                            newArea = true
                        }
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
            #if DEBUG
            // COCKPIT_TODO_MODE=today oeffnet „Heute" - fuer Aufnahmen.
            .onAppear {
                if let wanted = ProcessInfo.processInfo.environment["COCKPIT_TODO_MODE"].flatMap(Mode.init) {
                    mode = wanted
                }
            }
            #endif
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
    /// Angefangene Unteraufgaben, je Hauptaufgabe - die Zeile unter der
    /// Liste ist ein leeres Feld, das man einfach befuellt.
    @State private var subDrafts: [String: String] = [:]
    @State private var detail: TodoItem?
    @FocusState private var typing: Bool
    @FocusState private var subFocus: String?

    var body: some View {
        List {
            if let message = store.errorMessage {
                ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(area.todos) { todo in
                    row(todo, under: nil)
                    ForEach(todo.children) { child in
                        row(child, under: todo)
                    }
                    if !todo.isDone {
                        ghostRow(under: todo)
                    }
                }
                if area.todos.isEmpty {
                    Text("Nichts offen.").foregroundStyle(.secondary)
                }
            } header: {
                // Der Name stand vorher im Titel - dort sitzt jetzt der Umschalter.
                Text("\(area.name) · " + (area.openCount == 1 ? "1 offen" : "\(area.openCount) offen"))
            } footer: {
                if area.hiddenDoneCount > 0, !store.showsHidden {
                    Text("\(area.hiddenDoneCount) ältere erledigte sind ausgeblendet – im Menü einblenden.")
                }
            }
            Section {
                HStack {
                    TextField("Neue Aufgabe", text: $newTitle)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("newTodo")
                    Button { submit() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addTodo")
                }
            }
        }
        .sheet(item: $detail) { todo in
            TodoDetailSheet(todo: todo, store: store, area: area,
                            isTopLevel: area.todos.contains { $0.id == todo.id })
        }
    }

    /// Die leere Zeile unter den Unteraufgaben: ein gestrichelter Kreis und
    /// ein Feld. Vorher steckte das Anlegen in einem Menue und in einer
    /// Wischaktion - und war damit fuer niemanden zu finden. Der Kreis allein
    /// sagt genug, ein Platzhaltertext daneben war Felix zu viel (2026-09-22);
    /// fuer VoiceOver bleibt die Beschriftung.
    private func ghostRow(under parent: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.title3)
                .foregroundStyle(.tertiary)
            TextField("", text: Binding(
                get: { subDrafts[parent.id] ?? "" },
                set: { subDrafts[parent.id] = $0 }))
                .focused($subFocus, equals: parent.id)
                .submitLabel(.done)
                .onSubmit { submitSub(under: parent) }
                .accessibilityLabel("Unteraufgabe")
                .accessibilityIdentifier("newSub-\(parent.id)")
        }
        .padding(.leading, 28)
        .contentShape(Rectangle())
        .onTapGesture { subFocus = parent.id }
    }

    private func submitSub(under parent: TodoItem) {
        let title = (subDrafts[parent.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        // Steht sofort da - auch ohne Netz; geschickt wird spaeter.
        guard store.add(title: title, to: area, under: parent) else { return }
        subDrafts[parent.id] = nil
        subFocus = nil
    }

    private func submit() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, store.add(title: title, to: area) else { return }
        newTitle = ""
        // Die Tastatur geht mit dem Eintrag zu - sonst steht sie vor der
        // Liste, und die neue Aufgabe ist nicht zu sehen.
        typing = false
    }

    /// - Parameter parent: die Aufgabe darueber, bei einer Unteraufgabe. Steht
    ///   die in „Heute", kommt die Unteraufgabe mit - einzeln holen gibt es dann nicht.
    private func row(_ todo: TodoItem, under parent: TodoItem?) -> some View {
        let canPin = parent?.today != true && (!todo.isDone || todo.today)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                store.toggle(todo)
            } label: {
                // Der echte Stand, sofort - und eine kleine Uhr daran, solange er
                // auf Netz wartet. Frueher ersetzte die Uhr den Haken, und man sah
                // nicht, ob die Aufgabe jetzt erledigt war.
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? Color.orange : Color.secondary)
                    .overlay(alignment: .bottomTrailing) {
                        if store.isWaiting(todo) { WaitingBadge() }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle-\(todo.id)")
            .accessibilityValue(store.isWaiting(todo) ? "wartet auf Netz" : "")

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(todo.title)
                        .strikethrough(todo.isDone)
                        .foregroundStyle(todo.isDone ? .secondary : .primary)
                    if let link = todo.link {
                        TodoLinkButton(link: link, todo: todo)
                    }
                }
                if todo.dueAt != nil || !todo.reminders.isEmpty {
                    HStack(spacing: 8) {
                        if let dueLabel = todo.dueLabel {
                            Text(dueLabel)
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
            // Die Sonne holt nach „Heute" und nimmt wieder raus - ein Tipp. Erst
            // sollte das Wischen nach rechts sein, aber das blaetternde TabView
            // nimmt sich jede waagerechte Geste und zeigt den naechsten Bereich.
            if canPin {
                Button { store.setToday(todo, !todo.today) } label: {
                    Image(systemName: todo.today ? "sun.max.fill" : "sun.max")
                        .font(.subheadline)
                        .foregroundStyle(todo.today ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(todo.today ? "Aus Heute nehmen" : "Nach Heute holen")
                .accessibilityValue(todo.today ? "in Heute" : "")
                .accessibilityIdentifier("today-\(todo.id)")
            }
            // Der Pfeil sagt, dass hinter der Zeile mehr ist: Faelligkeit
            // und Erinnerungen. Ohne ihn fand das niemand.
            Button { detail = todo } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, parent == nil ? 0 : 28)
        .contextMenu {
            if canPin {
                Button { store.setToday(todo, !todo.today) } label: {
                    Label(todo.today ? "Aus Heute nehmen" : "Nach Heute holen",
                          systemImage: todo.today ? "sun.max" : "sun.max.fill")
                }
            }
            Button { detail = todo } label: {
                Label("Fälligkeit und Erinnerungen …", systemImage: "calendar.badge.clock")
            }
            Button(role: .destructive) {
                store.delete(todo)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.delete(todo)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}

/// Der Pfeil neben dem Titel oeffnet den Link in Safari. Ein eigener Knopf
/// statt der ganzen Zeile: der Tipp auf den Text oeffnet weiter das Blatt,
/// und die Wischaktionen bleiben, wo sie sind. Das Polster vergroessert
/// die Tippflaeche, ohne die Zeile hoeher zu machen.
struct TodoLinkButton: View {

    let link: URL
    let todo: TodoItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(link) } label: {
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(todo.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link öffnen")
        .accessibilityIdentifier("link-\(todo.id)")
    }
}

/// Faelligkeit und Erinnerungen einer Aufgabe.
struct TodoDetailSheet: View {

    let todo: TodoItem
    let store: TodoStore
    /// `nil` bei einer Aufgabe ohne Bereich - die bekommt keine Unteraufgaben.
    let area: TodoArea?
    /// Nur Hauptaufgaben bekommen Unteraufgaben - eine Ebene, nicht mehr.
    let isTopLevel: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var reminderAt = Date().addingTimeInterval(3600)
    @State private var newSub = ""

    init(todo: TodoItem, store: TodoStore, area: TodoArea?, isTopLevel: Bool) {
        self.todo = todo
        self.store = store
        self.area = area
        self.isTopLevel = isTopLevel
        _title = State(initialValue: todo.title)
        _hasDue = State(initialValue: todo.dueAt != nil)
        _due = State(initialValue: todo.dueAt?.startOfDay() ?? Date())
    }

    /// Der Stand aus dem Brett, nicht die Kopie vom Oeffnen: nach einer neuen
    /// Erinnerung soll sie hier auch stehen.
    private var live: TodoItem { store.current(todo) ?? todo }

    private func addSub() {
        let text = newSub.trimmingCharacters(in: .whitespaces)
        guard let area, !text.isEmpty, store.add(title: text, to: area, under: live) else { return }
        newSub = ""
    }

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
                if isTopLevel, area != nil {
                    Section("Unteraufgaben") {
                        ForEach(live.children) { child in
                            Text(child.title)
                                .strikethrough(child.isDone)
                                .foregroundStyle(child.isDone ? .secondary : .primary)
                        }
                        HStack {
                            TextField("Neue Unteraufgabe", text: $newSub)
                                .submitLabel(.done)
                                .onSubmit { addSub() }
                            Button { addSub() } label: { Image(systemName: "plus.circle.fill") }
                                .disabled(newSub.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                // Erinnerungen schickt der Dienst - fuer eine Aufgabe, die er noch nicht
                // kennt (ohne Netz angelegt), gibt es hier nichts zu stellen.
                if store.isKnownToService(live) {
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
            }
            .navigationTitle("Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let day = hasDue ? CalendarDate(date: due) : nil
                        // Gilt sofort, auch ohne Netz - das Blatt kann zu.
                        if store.update(live, title: title.trimmingCharacters(in: .whitespaces), dueAt: day) {
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
