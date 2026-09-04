import Foundation

/// Alles, was die Einkaufsliste braucht, in einer Antwort. Der Dienst schickt
/// nach jeder Aenderung das ganze Brett zurueck, wie beim To-Do - die App
/// ersetzt ihren Stand und setzt nichts zusammen. Und der Offline-Cache hat
/// damit genau eine Antwort zu merken.
struct ShoppingBoard: Decodable, Equatable, Sendable {
    /// Der Name, der zum Token gehoert - wer hier „ich" ist.
    var me: String
    /// In der Reihenfolge des Supermarkt-Rundgangs - die Liste ist danach
    /// sortiert, und die Reihenfolge kommt vom Dienst, nicht aus der App.
    var categories: [ShoppingCategory]
    var items: [ShoppingItem]
    var dishes: [ShoppingDish]
    var recurring: [ShoppingRule]

    func category(_ key: String) -> ShoppingCategory? {
        categories.first { $0.key == key }
    }
}

/// Eine Kategorie: Schluessel, Beschriftung, ein Emoji fuers Web und ein
/// SF Symbol fuer die App. Der Dienst ordnet jeden Eintrag einer zu
/// (Woerterbuch, Wortregeln, Gelerntes); die App zeigt nur das Symbol.
struct ShoppingCategory: Decodable, Identifiable, Equatable, Sendable {
    var key: String
    var label: String
    var emoji: String
    var symbol: String

    var id: String { key }
}

/// Ein Eintrag auf der Liste. `var`, nicht `let`: ohne Netz aendert die App
/// ihren Stand selbst, bis der Dienst wieder antwortet.
struct ShoppingItem: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var quantity: String?
    /// Frei - oder der Name des Gerichts, wenn der Eintrag aus einem kam.
    var note: String?
    var addedAt: Date
    var addedBy: String
    var checkedAt: Date?
    var checkedBy: String?
    var dishId: String?
    var ruleId: String?
    /// Der Schluessel der Kategorie - vom Dienst vergeben, in der App
    /// aenderbar (und der Dienst merkt sich das fuer den Namen).
    var category: String?

    var isChecked: Bool { checkedAt != nil }

    /// Ohne Netz angelegt und noch nicht beim Dienst: die Kennung ist
    /// erfunden, und Haken oder Loeschen darauf gingen ins Leere.
    var isLocal: Bool { id.hasPrefix(ShoppingItem.localPrefix) }

    static let localPrefix = "local-"
}

struct ShoppingIngredient: Codable, Equatable, Hashable, Sendable {
    var name: String
    var quantity: String?
}

/// Ein Gericht: eine Zutatenliste, die mit einem Tipp komplett auf die
/// Einkaufsliste geht.
struct ShoppingDish: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var ingredients: [ShoppingIngredient]
    var createdAt: Date
}

/// Etwas, das von selbst wiederkommt - Klopapier alle 14 Tage. Der Dienst
/// setzt es auf die Liste, sobald `nextAt` erreicht ist, und rechnet ab dem
/// Abhaken neu.
struct ShoppingRule: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var quantity: String?
    var everyDays: Int
    var nextAt: CalendarDate
    var createdAt: Date
}

// MARK: - Was die App schickt

/// `category` nur, wenn jemand sie von Hand gewaehlt hat - sonst ordnet
/// der Dienst zu und lernt nichts Falsches.
struct ShoppingItemDraft: Encodable, Sendable {
    let name: String
    let quantity: String?
    let note: String?
    let category: String?
}

struct ShoppingDishDraft: Encodable, Sendable {
    let name: String
    let ingredients: [ShoppingIngredient]
}

/// `nextAt` als ISO-Datum (`yyyy-MM-dd`), wie der Dienst es liest.
struct ShoppingRuleDraft: Encodable, Sendable {
    let name: String
    let quantity: String?
    let everyDays: Int
    let nextAt: String?
}
