import Foundation
import SwiftUI

/// Haelt das Brett und schickt Haken, neue Aufgaben, neue Bereiche.
///
/// Aufgaben anlegen, abhaken, aendern und loeschen sind sofort zu sehen: sie
/// gehen in die Warteschlange (`PendingChanges`), das Brett zeigt den Stand des
/// Dienstes und darueber, was wartet (`TodoOverlay`). Ohne Netz bleibt das so,
/// bis es wieder da ist - auch ueber einen Neustart. Lehnt der Dienst etwas ab,
/// verschwindet es aus der Anzeige, und eine Meldung sagt, was nicht ging.
///
/// Bereiche und Erinnerungen bleiben auf Antwort angewiesen: sie aendern das
/// Brett fuer alle Seiten bzw. brauchen eine Aufgabe, die der Dienst kennt.
@MainActor
@Observable
final class TodoStore {

    private let api = TodoAPI()
    private var queue: PendingChanges { PendingChanges.shared }

    /// Der Stand des Dienstes - ohne das, was noch wartet.
    private(set) var serverBoard: TodoBoard?
    /// Die Nummer der Anfrage, aus der `serverBoard` stammt. Ein aelterer Stand
    /// ersetzt ihn nicht - etwa ein Abruf, der vor einem Haken losging und nach
    /// dessen Antwort ankommt.
    @ObservationIgnored private var serverSequence = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false
    /// Auch die aelteren erledigten zeigen.
    var showsHidden = false

    /// Das Brett, wie es zu sehen ist: Stand des Dienstes plus Wartendes.
    var board: TodoBoard? {
        serverBoard.map { TodoOverlay.apply(queue.changes(for: .todo).compactMap(\.todo), to: $0) }
    }

    var areas: [TodoArea] { board?.areas ?? [] }

    /// „Heute", wie es zu sehen ist - samt dem, was wartet.
    var today: TodoToday { board?.today ?? .empty }

    private static let registeredTokenKey = "todo.registeredPushToken"

    init() {
        queue.observe(.todo) { [weak self] event in self?.handle(event) }
    }

    /// Ob an dieser Aufgabe etwas auf Netz wartet - die Uhr an der Zeile.
    func isWaiting(_ todo: TodoItem) -> Bool {
        queue.showsWaiting(todo.id, on: .todo)
    }

    /// Ob es die Aufgabe beim Dienst schon gibt - Erinnerungen brauchen das.
    func isKnownToService(_ todo: TodoItem) -> Bool {
        !queue.isLocal(todo.id, on: .todo)
    }

    func load() async {
        isLoading = serverBoard == nil
        defer { isLoading = false }
        // Ein Abruf neben einem laufenden Schreiben holte womoeglich einen Stand
        // ohne das gerade Geschriebene.
        await queue.waitUntilIdle(.todo, timeout: .seconds(3))
        let sequence = queue.nextSequence()
        do {
            let board = try await api.board(includeHidden: showsHidden)
            apply(board, sequence: sequence)
            await registerForPushIfNeeded()
        } catch {
            report(error, notify: false)
        }
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

    // MARK: - Aufgaben (sofort sichtbar)

    /// Abhaken und zuruecknehmen nach dem, was zu sehen ist - auch wenn das
    /// vorige Abhaken noch wartet.
    func toggle(_ todo: TodoItem) {
        queue.enqueue(.todo(.setDone(id: todo.id, done: !todo.isDone, at: Date())), label: todo.title)
    }

    /// - Returns: `false`, wenn der Text zu lang ist - das sagt der Dienst sonst
    ///   erst beim Nachsenden.
    @discardableResult
    func add(title: String, to area: TodoArea, under parent: TodoItem? = nil) -> Bool {
        guard checked(title) else { return false }
        let id = UUID().uuidString.lowercased()
        queue.enqueue(.todo(.create(id: id, areaId: area.id, parentId: parent?.id, title: title,
                                    dueAt: nil, at: Date())), label: title)
        return true
    }

    /// Eine Aufgabe ohne Bereich - sie steht nur in „Heute".
    @discardableResult
    func addToday(title: String) -> Bool {
        guard checked(title) else { return false }
        let id = UUID().uuidString.lowercased()
        queue.enqueue(.todo(.create(id: id, areaId: nil, parentId: nil, title: title, dueAt: nil, at: Date(),
                                    today: true)), label: title)
        return true
    }

    /// Nach „Heute" holen (ans Ende) oder wieder rausnehmen.
    func setToday(_ todo: TodoItem, _ today: Bool) {
        queue.enqueue(.todo(.setToday(id: todo.id, today: today)), label: todo.title)
    }

    /// Nach dem Ziehen in „Heute": die offenen in ihrer neuen Reihenfolge.
    /// Erledigtes steht ohnehin darunter und zieht nicht mit.
    func moveToday(from source: IndexSet, to destination: Int) {
        var ids = today.items.filter { !$0.todo.isDone }.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        queue.enqueue(.todo(.orderToday(ids: ids)), label: "Heute")
    }

    @discardableResult
    func update(_ todo: TodoItem, title: String, dueAt: CalendarDate?) -> Bool {
        guard checked(title) else { return false }
        queue.enqueue(.todo(.update(id: todo.id, title: title, dueAt: dueAt)), label: title)
        return true
    }

    func delete(_ todo: TodoItem) {
        queue.enqueue(.todo(.delete(id: todo.id)), label: todo.title)
    }

    /// Wie der Dienst: ein Text, hoechstens 200 Zeichen.
    private func checked(_ title: String) -> Bool {
        guard title.count <= 200 else {
            report(Message("Der Text darf höchstens 200 Zeichen haben."), notify: true)
            return false
        }
        return !title.isEmpty
    }

    /// Der aktuelle Stand einer Aufgabe nach einem Neuladen - fuer ein Blatt,
    /// das offen bleibt, waehrend sich das Brett darunter aendert.
    func current(_ todo: TodoItem) -> TodoItem? {
        // Aufgaben ohne Bereich stehen nur in „Heute".
        for item in areas.flatMap(\.todos) + today.items.map(\.todo) {
            if item.id == todo.id { return item }
            if let child = item.children.first(where: { $0.id == todo.id }) { return child }
        }
        return nil
    }

    // MARK: - Erinnerungen und Bereiche (mit Antwort)

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

    @discardableResult
    func addArea(name: String) async -> Bool {
        await perform { try await api.createArea(name: name) }
    }

    @discardableResult
    func renameArea(_ area: TodoArea, to name: String) async -> Bool {
        await perform { try await api.renameArea(id: area.id, name: name) }
    }

    func deleteArea(_ area: TodoArea) async {
        await perform { try await api.deleteArea(id: area.id) }
    }

    func setShowsHidden(_ value: Bool) async {
        showsHidden = value
        await load()
    }

    // MARK: - Innereien

    @discardableResult
    private func perform(_ call: () async throws -> TodoBoard) async -> Bool {
        let sequence = queue.nextSequence()
        do {
            apply(try await call(), sequence: sequence)
            return true
        } catch {
            // Ein Fehler hier kommt oft, waehrend ein Blatt oder ein Dialog offen ist -
            // die Meldung oben sieht man dann, die Leiste im Inhalt nicht.
            report(error, notify: true)
            return false
        }
    }

    private func apply(_ board: TodoBoard, sequence: Int) {
        guard sequence > serverSequence else { return }
        serverSequence = sequence
        serverBoard = board
        errorMessage = nil
        isAccessProblem = false
    }

    private func handle(_ event: PendingEvent) {
        switch event {
        case .delivered(let data, let sequence):
            // Die Antwort ist das ganze Brett - ausser mit „aeltere erledigte zeigen“:
            // dann fehlen ihr die ausgeblendeten, und ein Abruf holt sie.
            if showsHidden {
                Task { await load() }
            } else if let board = try? APIClient.decoder().decode(TodoBoard.self, from: data) {
                apply(board, sequence: sequence)
            }
        case .rejected, .drained:
            // Darunter hat sich vielleicht mehr geaendert (im Browser, auf dem Mac).
            Task { await load() }
        }
    }

    private func report(_ error: Error, notify: Bool) {
        if let apiError = error as? APIError, case .notAuthorised = apiError {
            isAccessProblem = true
        }
        errorMessage = error.localizedDescription
        if notify { NoticeCenter.shared.show(error.localizedDescription) }
    }

    private struct Message: LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }
}
