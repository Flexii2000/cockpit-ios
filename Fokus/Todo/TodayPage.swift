import SwiftUI

/// „Heute": die geholten Aufgaben in Felix' Reihenfolge. Darunter, was heute
/// erledigt wurde, unten das Feld fuer Aufgaben, die keiner Liste gehoeren.
///
/// Geordnet wird ueber „Ordnen" mit den Griffen von iOS - die gehen auf dem
/// iPhone immer. Lange druecken und ziehen ohne Bearbeiten-Modus haengt davon
/// ab, ob die Liste Ziehen zulaesst (auf dem iPhone ab Werk aus); `onMove` gilt
/// fuer beides. Pruefen liess sich keins davon: XCUITest bewegt in dieser Liste
/// auch die Griffe nicht (26.10.). Rausnehmen und Loeschen liegen auf dem
/// Wischen nach links; hier blaettert nichts, anders als in den Bereichen.
struct TodayPage: View {

    let store: TodoStore

    @State private var newTitle = ""
    @State private var detail: TodoTodayItem?
    @State private var editMode: EditMode = .inactive
    @FocusState private var typing: Bool

    private var open: [TodoTodayItem] { store.today.items.filter { !$0.todo.isDone } }
    private var done: [TodoTodayItem] { store.today.items.filter(\.todo.isDone) }

    var body: some View {
        List {
            if let message = store.errorMessage {
                ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(open) { item in
                    TodayRow(item: item, store: store) { detail = item }
                }
                .onMove { store.moveToday(from: $0, to: $1) }
                ForEach(done) { item in
                    TodayRow(item: item, store: store) { detail = item }
                }
                if store.today.items.isEmpty {
                    Text("Nichts offen.").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    // Deutsch wie der Rest der App - auch auf einem Geraet in anderer Sprache.
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.twoDigits)
                                            .locale(Locale(identifier: "de_DE"))) + " · "
                         + (store.today.openCount == 1 ? "1 offen" : "\(store.today.openCount) offen"))
                    Spacer()
                    if open.count > 1 || editMode.isEditing {
                        Button(editMode.isEditing ? "Fertig" : "Ordnen") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .fontWeight(.semibold)
                        .textCase(nil)
                        .accessibilityIdentifier("orderToday")
                    }
                }
            }
            Section {
                HStack {
                    TextField("Neue Aufgabe", text: $newTitle)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("newTodayTodo")
                    Button { submit() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addTodayTodo")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(item: $detail) { item in
            let area = store.areas.first { $0.id == item.areaId }
            TodoDetailSheet(todo: item.todo, store: store, area: area,
                            isTopLevel: item.parentId == nil && area != nil)
        }
    }

    private func submit() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, store.addToday(title: title) else { return }
        newTitle = ""
        typing = false
    }
}

/// Eine Zeile in „Heute": wie in den Bereichen, dazu darunter, woher sie kommt
/// („Uni › Hausarbeit"). Eine geholte Hauptaufgabe hat ihre Unteraufgaben in
/// derselben Zeile - so zieht sie sie beim Ordnen mit.
private struct TodayRow: View {

    let item: TodoTodayItem
    let store: TodoStore
    let showDetail: () -> Void

    private var todo: TodoItem { item.todo }

    /// Bereich und Aufgabe darueber; bei einer Aufgabe ohne Bereich nichts.
    private var origin: String? {
        let parts = [item.areaName, item.parentTitle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                check(todo)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(todo.title)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                        if let link = todo.link {
                            TodoLinkButton(link: link, todo: todo)
                        }
                    }
                    if origin != nil || todo.dueAt != nil || !todo.reminders.isEmpty {
                        HStack(spacing: 8) {
                            if let origin {
                                Text(origin).foregroundStyle(.secondary)
                            }
                            if let dueLabel = todo.dueLabel {
                                Text(dueLabel)
                                    .foregroundStyle(todo.isOverdue ? Color.red : Color.secondary)
                                    .fontWeight(todo.isOverdue ? .semibold : .regular)
                            }
                            if !todo.reminders.isEmpty {
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
                .onTapGesture(perform: showDetail)
                Spacer(minLength: 0)
                Button(action: showDetail) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            ForEach(todo.children) { child in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    check(child)
                    Text(child.title)
                        .strikethrough(child.isDone)
                        .foregroundStyle(child.isDone ? .secondary : .primary)
                }
                .padding(.leading, 28)
            }
        }
        .accessibilityIdentifier("todayRow-\(todo.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Ohne Bereich gibt es kein Woanders - dann ist Rausnehmen Loeschen.
            if item.isAdHoc {
                Button(role: .destructive) { store.delete(todo) } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } else {
                Button { store.setToday(todo, false) } label: {
                    Label("Raus", systemImage: "sun.max")
                }
                .tint(.orange)
            }
        }
    }

    /// Der Haken - wie in den Bereichen, mit der Uhr, solange er auf Netz wartet.
    private func check(_ todo: TodoItem) -> some View {
        Button {
            store.toggle(todo)
        } label: {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(todo.isDone ? Color.orange : Color.secondary)
                .overlay(alignment: .bottomTrailing) {
                    if store.isWaiting(todo) { WaitingBadge() }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("todayToggle-\(todo.id)")
        .accessibilityValue(store.isWaiting(todo) ? "wartet auf Netz" : "")
    }
}
