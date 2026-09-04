import Foundation

/// Haelt die Liste, die Gerichte und die Regeln - und zeigt ohne Netz das,
/// was im Postausgang liegt, schon so, als waere es durch.
///
/// Der Grund ist der Supermarkt: dort fehlt oft das Netz, und ein Haken, der
/// erst beim naechsten Empfang zu sehen ist, ist im Laden nichts wert. Ohne
/// Netz aendert der Store deshalb seinen Stand selbst; sobald der Dienst
/// wieder antwortet, ersetzt dessen Brett alles.
@MainActor
@Observable
final class ShoppingStore {

    private let api = ShoppingAPI()

    private(set) var board: ShoppingBoard?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false
    /// Eintraege, deren Aenderung ohne Netz im Postausgang liegt.
    private(set) var pendingIDs: Set<String> = []

    var items: [ShoppingItem] { board?.items ?? [] }
    var openItems: [ShoppingItem] { items.filter { !$0.isChecked } }
    var checkedItems: [ShoppingItem] { items.filter(\.isChecked) }
    var dishes: [ShoppingDish] { board?.dishes ?? [] }
    var rules: [ShoppingRule] { board?.recurring ?? [] }
    /// Wer hier eintraegt - der Name zum Token.
    var me: String { board?.me ?? "ich" }

    func load() async {
        isLoading = board == nil
        defer { isLoading = false }
        await perform { try await api.board() }
        if await Outbox.shared.count == 0 { pendingIDs.removeAll() }
    }

    // MARK: - Liste

    @discardableResult
    func add(name: String, quantity: String?) async -> Bool {
        let draft = ShoppingItemDraft(name: name, quantity: quantity, note: nil, category: nil)
        return await perform({ try await api.addItem(draft) }) {
            // Bis der Dienst antwortet, steht der Eintrag mit erfundener
            // Kennung in der Liste. Das naechste Brett bringt die echte.
            let local = ShoppingItem(id: Self.localID(), name: name, quantity: quantity, note: nil,
                                     addedAt: Date(), addedBy: me, checkedAt: nil, checkedBy: nil,
                                     dishId: nil, ruleId: nil, category: nil)
            board?.items.append(local)
            pendingIDs.insert(local.id)
        }
    }

    func toggle(_ item: ShoppingItem) async {
        guard !item.isLocal else { return }
        let wasChecked = item.isChecked
        await perform({
            if wasChecked {
                try await api.uncheck(id: item.id)
            } else {
                try await api.check(id: item.id)
            }
        }) {
            guard let i = index(of: item.id) else { return }
            board?.items[i].checkedAt = wasChecked ? nil : Date()
            board?.items[i].checkedBy = wasChecked ? nil : me
            pendingIDs.insert(item.id)
        }
    }

    /// - Parameter category: nur mitgeben, wenn jemand sie bewusst gewaehlt
    ///   hat - der Dienst lernt daraus fuer den Namen.
    @discardableResult
    func update(_ item: ShoppingItem, name: String, quantity: String?, note: String?,
                category: String?) async -> Bool {
        guard !item.isLocal else { return false }
        let draft = ShoppingItemDraft(name: name, quantity: quantity, note: note, category: category)
        return await perform({ try await api.updateItem(id: item.id, draft: draft) }) {
            guard let i = index(of: item.id) else { return }
            board?.items[i].name = name
            board?.items[i].quantity = quantity
            board?.items[i].note = note
            if let category { board?.items[i].category = category }
            pendingIDs.insert(item.id)
        }
    }

    func delete(_ item: ShoppingItem) async {
        guard !item.isLocal else { return }
        await perform({ try await api.deleteItem(id: item.id) }) {
            board?.items.removeAll { $0.id == item.id }
        }
    }

    func clearChecked() async {
        await perform({ try await api.clearChecked() }) {
            board?.items.removeAll(where: \.isChecked)
        }
    }

    // MARK: - Gerichte

    /// Alle Zutaten des Gerichts auf die Liste - auch ohne Netz.
    @discardableResult
    func addDish(_ dish: ShoppingDish) async -> Bool {
        await perform({ try await api.addDish(id: dish.id) }) {
            for ingredient in dish.ingredients {
                let local = ShoppingItem(id: Self.localID(), name: ingredient.name,
                                         quantity: ingredient.quantity, note: dish.name,
                                         addedAt: Date(), addedBy: me, checkedAt: nil, checkedBy: nil,
                                         dishId: dish.id, ruleId: nil, category: nil)
                board?.items.append(local)
                pendingIDs.insert(local.id)
            }
        }
    }

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

    // MARK: - Regeln

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

    private func index(of id: String) -> Int? {
        board?.items.firstIndex { $0.id == id }
    }

    private static func localID() -> String {
        ShoppingItem.localPrefix + UUID().uuidString
    }

    /// Fuehrt einen Aufruf aus und uebernimmt das Brett. Liegt der Aufruf
    /// ohne Netz im Postausgang, macht `whenQueued` den Stand hier passend.
    ///
    /// Kein optionaler Abschluss: der waere "escaping", und jeder Aufrufer
    /// muesste `self.` vor jede Zeile schreiben.
    @discardableResult
    private func perform(_ call: () async throws -> ShoppingBoard,
                         whenQueued: () -> Void = {}) async -> Bool {
        do {
            apply(try await call())
            return true
        } catch APIError.queued {
            whenQueued()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func apply(_ board: ShoppingBoard) {
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
