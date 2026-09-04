import Foundation

/// Haelt das Brett und schickt Haken, neue Aufgaben, neue Bereiche.
@MainActor
@Observable
final class TodoStore {

    private let api = TodoAPI()

    private(set) var board: TodoBoard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false
    /// Aufgaben, deren Haken ohne Netz im Postausgang liegt.
    private(set) var pendingIDs: Set<String> = []
    /// Auch die aelteren erledigten zeigen.
    var showsHidden = false

    var areas: [TodoArea] { board?.areas ?? [] }

    private static let registeredTokenKey = "todo.registeredPushToken"

    func load() async {
        isLoading = board == nil
        defer { isLoading = false }
        if await perform({ try await api.board(includeHidden: showsHidden) }) {
            await registerForPushIfNeeded()
        }
        if await Outbox.shared.count == 0 { pendingIDs.removeAll() }
    }

    /// Meldet die Push-Kennung an, sobald der Dienst erreichbar war - einmal je
    /// Kennung, nicht bei jedem Laden.
    private func registerForPushIfNeeded() async {
        guard let token = Notifications.deviceToken else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.registeredTokenKey) != token else { return }
        do {
            try await api.registerDevice(token: token)
            defaults.set(token, forKey: Self.registeredTokenKey)
        } catch {
            print("To-Do-Push nicht angemeldet: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func update(_ todo: TodoItem, title: String, dueAt: CalendarDate?) async -> Bool {
        await perform { try await api.update(id: todo.id, title: title, dueAt: dueAt) }
    }

    @discardableResult
    func addReminder(to todo: TodoItem, at: Date) async -> Bool {
        // Ohne Erlaubnis kommt keine Erinnerung an - also jetzt fragen, wo
        // der Zusammenhang klar ist.
        await Notifications.requestPermission()
        return await perform { try await api.addReminder(id: todo.id, at: at) }
    }

    func deleteReminder(_ reminder: TodoReminder, from todo: TodoItem) async {
        await perform { try await api.deleteReminder(id: todo.id, reminderId: reminder.id) }
    }

    /// Der aktuelle Stand einer Aufgabe nach einem Neuladen - fuer ein Blatt,
    /// das offen bleibt, waehrend sich das Brett darunter aendert.
    func current(_ todo: TodoItem) -> TodoItem? {
        for area in areas {
            for item in area.todos {
                if item.id == todo.id { return item }
                if let child = item.children.first(where: { $0.id == todo.id }) { return child }
            }
        }
        return nil
    }

    func toggle(_ todo: TodoItem) async {
        do {
            let updated = todo.isDone
                ? try await api.reopen(id: todo.id)
                : try await api.done(id: todo.id)
            apply(updated)
        } catch APIError.queued {
            pendingIDs.insert(todo.id)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    @discardableResult
    func add(title: String, to area: TodoArea, under parent: TodoItem? = nil) async -> Bool {
        await perform { try await api.create(TodoDraft(areaId: area.id, parentId: parent?.id, title: title, dueAt: nil)) }
    }

    func delete(_ todo: TodoItem) async {
        await perform { try await api.delete(id: todo.id) }
    }

    @discardableResult
    func addArea(name: String) async -> Bool {
        await perform { try await api.createArea(name: name) }
    }

    func renameArea(_ area: TodoArea, to name: String) async {
        await perform { try await api.renameArea(id: area.id, name: name) }
    }

    func deleteArea(_ area: TodoArea) async {
        await perform { try await api.deleteArea(id: area.id) }
    }

    func setShowsHidden(_ value: Bool) async {
        showsHidden = value
        await load()
    }

    @discardableResult
    private func perform(_ call: () async throws -> TodoBoard) async -> Bool {
        do {
            apply(try await call())
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func apply(_ board: TodoBoard) {
        self.board = board
        errorMessage = nil
        isAccessProblem = false
    }

    private func report(_ error: Error) {
        if let apiError = error as? APIError, case .notAuthorised = apiError {
            isAccessProblem = true
        }
        errorMessage = error.localizedDescription
    }
}
