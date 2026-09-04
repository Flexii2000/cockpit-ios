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

    func load() async {
        isLoading = board == nil
        defer { isLoading = false }
        await perform { try await api.board(includeHidden: showsHidden) }
        if await Outbox.shared.count == 0 { pendingIDs.removeAll() }
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
        await perform { try await api.create(TodoDraft(areaId: area.id, parentId: parent?.id, title: title)) }
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
