import Foundation

/// Haelt die Liste, die Gerichte und die Regeln.
///
/// Was im Laden passiert - hinzufuegen, abhaken, aendern, loeschen, „Abgehakte
/// entfernen“, ein Gericht auf die Liste - ist sofort zu sehen: es geht in die
/// Warteschlange (`PendingChanges`), und die Liste zeigt den Stand des Dienstes
/// mit dem, was wartet, darueber (`ShoppingOverlay`). Im Supermarkt fehlt oft
/// das Netz; ein Haken, der erst nach 30 s Warten oder beim naechsten Empfang zu
/// sehen ist, ist dort nichts wert. Lehnt der Dienst etwas ab, verschwindet es
/// aus der Anzeige, und eine Meldung sagt, was nicht ging.
///
/// Gerichte und Regeln pflegen ist Schreibtischarbeit: das wartet auf die
/// Antwort und sagt es, wenn es nicht geht.
@MainActor
@Observable
final class ShoppingStore {

    private let api = ShoppingAPI()
    private var queue: PendingChanges { PendingChanges.shared }

    /// Der Stand des Dienstes - ohne das, was noch wartet.
    private(set) var serverBoard: ShoppingBoard?
    @ObservationIgnored private var serverSequence = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false

    /// Die Liste, wie sie zu sehen ist: Stand des Dienstes plus Wartendes.
    var board: ShoppingBoard? {
        serverBoard.map { ShoppingOverlay.apply(queue.changes(for: .shopping).compactMap(\.shopping), to: $0) }
    }

    var items: [ShoppingItem] { board?.items ?? [] }
    var openItems: [ShoppingItem] { items.filter { !$0.isChecked } }
    var checkedItems: [ShoppingItem] { items.filter(\.isChecked) }
    var dishes: [ShoppingDish] { board?.dishes ?? [] }
    var rules: [ShoppingRule] { board?.recurring ?? [] }
    /// Wer hier eintraegt - der Name zum Token.
    var me: String { board?.me ?? "ich" }

    init() {
        queue.observe(.shopping) { [weak self] event in self?.handle(event) }
    }

    /// Ob an diesem Eintrag etwas auf Netz wartet - die Uhr an der Zeile.
    func isWaiting(_ item: ShoppingItem) -> Bool {
        queue.showsWaiting(item.id, on: .shopping)
    }

    func load() async {
        isLoading = serverBoard == nil
        defer { isLoading = false }
        await queue.waitUntilIdle(.shopping, timeout: .seconds(3))
        let sequence = queue.nextSequence()
        do {
            apply(try await api.board(), sequence: sequence)
        } catch {
            report(error, notify: false)
        }
    }

    // MARK: - Liste (sofort sichtbar)

    /// Derselbe Name (egal wie geschrieben) wird wie beim Dienst ein Eintrag mit
    /// zusammengefasster Menge - das zeigt die Liste sofort so.
    func add(name: String, quantity: String?) {
        let id = UUID().uuidString.lowercased()
        queue.enqueue(.shopping(.add(id: id, name: name, quantity: quantity, note: nil, category: nil,
                                     at: Date(), by: me)), label: name)
    }

    /// Abhaken und zuruecknehmen nach dem, was zu sehen ist.
    func toggle(_ item: ShoppingItem) {
        queue.enqueue(.shopping(.setChecked(id: item.id, checked: !item.isChecked, at: Date(), by: me)),
                      label: item.name)
    }

    /// - Parameter category: nur mitgeben, wenn jemand sie bewusst gewaehlt
    ///   hat - der Dienst lernt daraus fuer den Namen.
    func update(_ item: ShoppingItem, name: String, quantity: String?, note: String?, category: String?) {
        queue.enqueue(.shopping(.update(id: item.id, name: name, quantity: quantity, note: note, category: category)),
                      label: name)
    }

    func delete(_ item: ShoppingItem) {
        queue.enqueue(.shopping(.delete(id: item.id)), label: item.name)
    }

    /// Nur, was hier abgehakt zu sehen ist: ein Haken, den die andere Person
    /// inzwischen gesetzt hat, bleibt beim Dienst stehen.
    func clearChecked() {
        let ids = checkedItems.map(\.id)
        guard !ids.isEmpty else { return }
        queue.enqueue(.shopping(.clearChecked(ids: ids)), label: "Abgehakte")
    }

    /// Alle Zutaten des Gerichts auf die Liste - auch ohne Netz, jede mit eigener
    /// Kennung, damit sich jede gleich abhaken laesst.
    func addDish(_ dish: ShoppingDish) {
        let items = dish.ingredients.map {
            ShoppingChange.DishItem(id: UUID().uuidString.lowercased(), name: $0.name, quantity: $0.quantity)
        }
        queue.enqueue(.shopping(.addDish(dishId: dish.id, dishName: dish.name, items: items, at: Date(), by: me)),
                      label: dish.name)
    }

    // MARK: - Gerichte und Regeln (mit Antwort)

    @discardableResult
    func createDish(name: String, ingredients: [ShoppingIngredient]) async -> Bool {
        await perform { try await api.createDish(ShoppingDishDraft(name: name, ingredients: ingredients)) }
    }

    @discardableResult
    func updateDish(_ dish: ShoppingDish, name: String, ingredients: [ShoppingIngredient]) async -> Bool {
        await perform { try await api.updateDish(id: dish.id, draft: ShoppingDishDraft(name: name, ingredients: ingredients)) }
    }

    func deleteDish(_ dish: ShoppingDish) async {
        await perform { try await api.deleteDish(id: dish.id) }
    }

    @discardableResult
    func createRule(name: String, quantity: String?, everyDays: Int, nextAt: CalendarDate) async -> Bool {
        await perform {
            try await api.createRule(ShoppingRuleDraft(name: name, quantity: quantity,
                                                       everyDays: everyDays, nextAt: nextAt.iso))
        }
    }

    @discardableResult
    func updateRule(_ rule: ShoppingRule, name: String, quantity: String?,
                    everyDays: Int, nextAt: CalendarDate) async -> Bool {
        await perform {
            try await api.updateRule(id: rule.id, draft: ShoppingRuleDraft(
                name: name, quantity: quantity, everyDays: everyDays, nextAt: nextAt.iso))
        }
    }

    func deleteRule(_ rule: ShoppingRule) async {
        await perform { try await api.deleteRule(id: rule.id) }
    }

    // MARK: - Innereien

    /// Fuehrt einen Aufruf aus und uebernimmt das Brett.
    @discardableResult
    private func perform(_ call: () async throws -> ShoppingBoard) async -> Bool {
        let sequence = queue.nextSequence()
        do {
            apply(try await call(), sequence: sequence)
            return true
        } catch {
            // Meist aus einem offenen Blatt heraus (Gericht, Regel) - die Meldung oben
            // sieht man dort, die Leiste im Inhalt dahinter nicht.
            report(error, notify: true)
            return false
        }
    }

    private func apply(_ board: ShoppingBoard, sequence: Int) {
        guard sequence > serverSequence else { return }
        serverSequence = sequence
        serverBoard = board
        errorMessage = nil
        isAccessProblem = false
    }

    private func handle(_ event: PendingEvent) {
        switch event {
        case .delivered(let data, let sequence):
            if let board = try? APIClient.decoder().decode(ShoppingBoard.self, from: data) {
                apply(board, sequence: sequence)
            }
        case .rejected, .drained:
            // Zwei Handys, eine Liste: darunter hat sich vielleicht mehr geaendert.
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
}
