import Foundation

/// Eine Aenderung an der Einkaufsliste, die die App sofort zeigt und spaeter
/// schickt - im Laden fehlt das Netz am haeufigsten.
///
/// Neue Eintraege (auch die Zutaten eines Gerichts) bekommen ihre Kennung von
/// der App. Der Dienst uebernimmt sie, legt bei derselben nichts doppelt an und
/// merkt sich, in welchem Eintrag sie aufging, wenn derselbe Name schon offen war.
enum ShoppingChange: Codable, Equatable, Sendable {
    case add(id: String, name: String, quantity: String?, note: String?, category: String?, at: Date, by: String)
    case setChecked(id: String, checked: Bool, at: Date, by: String)
    case update(id: String, name: String, quantity: String?, note: String?, category: String?)
    case delete(id: String)
    /// Nur die Eintraege, die die App abgehakt sah - ein Haken der anderen Person,
    /// der waehrenddessen dazukam, bleibt.
    case clearChecked(ids: [String])
    case addDish(dishId: String, dishName: String, items: [DishItem], at: Date, by: String)

    /// Eine Zutat mit der Kennung, die die App ihr gibt.
    struct DishItem: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let quantity: String?
    }

    var target: String? {
        switch self {
        case .add(let id, _, _, _, _, _, _), .setChecked(let id, _, _, _), .update(let id, _, _, _, _), .delete(let id): id
        case .clearChecked, .addDish: nil
        }
    }

    var role: PendingRole {
        switch self {
        case .add: .create
        case .setChecked: .state
        case .update: .edit
        case .delete: .delete
        case .clearChecked, .addDish: .other
        }
    }

    var request: PendingRequest {
        switch self {
        case .add(let id, let name, let quantity, let note, let category, _, _):
            PendingRequest(method: "POST", path: "/api/items",
                           body: Self.json(ShoppingItemDraft(name: name, quantity: quantity, note: note,
                                                             category: category, id: id)))
        case .setChecked(let id, let checked, _, _):
            checked ? PendingRequest(method: "POST", path: "/api/items/\(id)/check", body: Data("{}".utf8))
                    : PendingRequest(method: "DELETE", path: "/api/items/\(id)/check")
        case .update(let id, let name, let quantity, let note, let category):
            PendingRequest(method: "PUT", path: "/api/items/\(id)",
                           body: Self.json(ShoppingItemDraft(name: name, quantity: quantity, note: note,
                                                             category: category)))
        case .delete(let id):
            PendingRequest(method: "DELETE", path: "/api/items/\(id)", notFoundMeansDone: true)
        case .clearChecked(let ids):
            PendingRequest(method: "POST", path: "/api/items/clear-checked", body: Self.json(ClearChecked(ids: ids)))
        case .addDish(let dishId, _, let items, _, _):
            PendingRequest(method: "POST", path: "/api/dishes/\(dishId)/add",
                           body: Self.json(DishAdd(items: items.map { DishAdd.Entry(name: $0.name, id: $0.id) })))
        }
    }

    /// Ein wartendes Hinzufuegen mit einer spaeteren Berichtigung.
    func folded(with change: ShoppingChange) -> ShoppingChange? {
        guard case .add(let id, _, _, _, let oldCategory, let at, let by) = self,
              case .update(let other, let name, let quantity, let note, let category) = change, other == id else { return nil }
        return .add(id: id, name: name, quantity: quantity, note: note, category: category ?? oldCategory, at: at, by: by)
    }

    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        let name = "„\(label)“"
        if status == 404 {
            return switch self {
            case .addDish: PendingNotice(text: "Das Gericht \(name) gibt es nicht mehr.", isInfo: true)
            default: PendingNotice(text: "\(name) stand nicht mehr auf der Liste.", isInfo: true)
            }
        }
        return switch self {
        case .add, .addDish: .error("\(name) kam nicht auf die Liste", message, status: status)
        case .setChecked(_, let checked, _, _):
            .error(checked ? "\(name) ließ sich nicht abhaken" : "\(name) ließ sich nicht zurücknehmen", message, status: status)
        case .update: .error("\(name) ließ sich nicht ändern", message, status: status)
        case .delete: .error("\(name) ließ sich nicht löschen", message, status: status)
        case .clearChecked: .error("Abgehakte ließen sich nicht entfernen", message, status: status)
        }
    }

    private struct ClearChecked: Encodable {
        let ids: [String]
    }

    private struct DishAdd: Encodable {
        let items: [Entry]
        struct Entry: Encodable {
            let name: String
            let id: String
        }
    }

    private static func json<T: Encodable>(_ value: T) -> Data? {
        try? APIClient.encoder().encode(value)
    }
}

/// Die Liste, wie die App sie zeigt: der Stand des Dienstes und darueber, was wartet.
///
/// Dieselben Regeln wie beim Dienst, soweit die Liste sie sichtbar macht: derselbe
/// Name (egal wie geschrieben) wird ein Eintrag mit zusammengefasster Menge, die
/// Reihenfolge folgt dem Rundgang der Kategorien. Nach dem Senden gilt wieder das
/// Brett des Dienstes - auch seine Kategorie fuer einen neuen Namen.
enum ShoppingOverlay {

    static func apply(_ changes: [ShoppingChange], to board: ShoppingBoard) -> ShoppingBoard {
        guard !changes.isEmpty else { return board }
        var items = board.items
        for change in changes {
            apply(change, to: &items)
        }
        var result = board
        result.items = sorted(items, categories: board.categories)
        return result
    }

    private static func apply(_ change: ShoppingChange, to items: inout [ShoppingItem]) {
        switch change {
        case .add(let id, let name, let quantity, let note, let category, let at, let by):
            guard !items.contains(where: { $0.id == id }) else { return }
            if let i = openIndex(named: name, in: items) {
                items[i].quantity = ShoppingQuantity.merge(items[i].quantity, quantity)
                items[i].note = mergeNotes(items[i].note, note)
                if let category { items[i].category = category }
                return
            }
            items.append(ShoppingItem(id: id, name: name, quantity: quantity, note: note, addedAt: at, addedBy: by,
                                      checkedAt: nil, checkedBy: nil, dishId: nil, ruleId: nil, category: category))
        case .setChecked(let id, let checked, let at, let by):
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            items[i].checkedAt = checked ? (items[i].checkedAt ?? at) : nil
            items[i].checkedBy = checked ? (items[i].checkedBy ?? by) : nil
        case .update(let id, let name, let quantity, let note, let category):
            guard let i = items.firstIndex(where: { $0.id == id }) else { return }
            items[i].name = name
            items[i].quantity = quantity
            items[i].note = note
            if let category { items[i].category = category }
        case .delete(let id):
            items.removeAll { $0.id == id }
        case .clearChecked(let ids):
            let set = Set(ids)
            items.removeAll { $0.isChecked && set.contains($0.id) }
        case .addDish(let dishId, let dishName, let entries, let at, let by):
            for entry in entries {
                guard !items.contains(where: { $0.id == entry.id }) else { continue }
                if let i = openIndex(named: entry.name, in: items) {
                    items[i].quantity = ShoppingQuantity.merge(items[i].quantity, entry.quantity)
                    items[i].note = mergeNotes(items[i].note, dishName)
                    if items[i].dishId == nil { items[i].dishId = dishId }
                    continue
                }
                items.append(ShoppingItem(id: entry.id, name: entry.name, quantity: entry.quantity, note: dishName,
                                          addedAt: at, addedBy: by, checkedAt: nil, checkedBy: nil,
                                          dishId: dishId, ruleId: nil, category: nil))
            }
        }
    }

    /// Wie `ShoppingService.nameKey`: ohne Rand, Leerraum zu einem, klein.
    static func nameKey(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func openIndex(named name: String, in items: [ShoppingItem]) -> Int? {
        let key = nameKey(name)
        return items.firstIndex { !$0.isChecked && nameKey($0.name) == key }
    }

    /// Wie `ShoppingService.mergeNotes`: eine Notiz, die schon dasteht, nicht doppelt.
    static func mergeNotes(_ a: String?, _ b: String?) -> String? {
        let x = a?.trimmingCharacters(in: .whitespaces) ?? ""
        let y = b?.trimmingCharacters(in: .whitespaces) ?? ""
        if x.isEmpty { return y.isEmpty ? nil : b }
        if y.isEmpty || x.lowercased() == y.lowercased() { return a }
        return x + ", " + y
    }

    /// Offene zuerst - nach Kategorie im Rundgang, darin aelteste oben -, dann die
    /// abgehakten, zuletzt abgehakte oben. Ohne Kategorie (neu, der Dienst hat noch
    /// nicht geraten) wie „Sonstiges“, also ans Ende.
    static func sorted(_ items: [ShoppingItem], categories: [ShoppingCategory]) -> [ShoppingItem] {
        let order = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1.key, $0) })
        let last = order["other"] ?? categories.count
        func rank(_ item: ShoppingItem) -> Int { item.category.flatMap { order[$0] } ?? last }
        return items.sorted { a, b in
            if a.isChecked != b.isChecked { return !a.isChecked }
            if let x = a.checkedAt, let y = b.checkedAt { return x > y }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.addedAt < b.addedAt
        }
    }
}
