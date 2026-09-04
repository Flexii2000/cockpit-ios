import Foundation

/// Die Endpunkte des Einkaufslisten-Dienstes.
///
/// Zugang ueber den Einkaufs-Cookie, den `Access.applyCookies()` fuer den
/// Pfad `/shopping-list` setzt - der Dienst nimmt denselben Cookie wie der
/// Browser nach `/shopping-list/setup?token=…`.
///
/// `queueWhenOffline` steht an allem, was im Laden passiert: Haken, neuer
/// Eintrag, Gericht auf die Liste. Dort fehlt das Netz am haeufigsten, und
/// genau dort muss die Liste trotzdem bedienbar sein. Gerichte und Regeln
/// pflegen ist Schreibtischarbeit - das darf scheitern und es sagen.
struct ShoppingAPI: Sendable {

    private let client: APIClient

    init(timeout: TimeInterval = 30) {
        client = APIClient(backend: .shopping, cookie: nil, timeout: timeout)
    }

    func board() async throws -> ShoppingBoard {
        try await client.get("/api/board")
    }

    // MARK: Liste

    func addItem(_ draft: ShoppingItemDraft) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/items", body: draft, queueWhenOffline: true)
    }

    func updateItem(id: String, draft: ShoppingItemDraft) async throws -> ShoppingBoard {
        try await client.send("PUT", "/api/items/\(id)", body: draft, queueWhenOffline: true)
    }

    func deleteItem(id: String) async throws -> ShoppingBoard {
        try await client.delete("/api/items/\(id)", queueWhenOffline: true)
    }

    /// Idempotent beim Dienst: ein Nachsenden aus dem Postausgang hakt nicht
    /// doppelt ab.
    func check(id: String) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/items/\(id)/check", body: Empty(), queueWhenOffline: true)
    }

    func uncheck(id: String) async throws -> ShoppingBoard {
        try await client.delete("/api/items/\(id)/check", queueWhenOffline: true)
    }

    func clearChecked() async throws -> ShoppingBoard {
        try await client.send("POST", "/api/items/clear-checked", body: Empty(), queueWhenOffline: true)
    }

    // MARK: Gerichte

    func createDish(_ draft: ShoppingDishDraft) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/dishes", body: draft)
    }

    func updateDish(id: String, draft: ShoppingDishDraft) async throws -> ShoppingBoard {
        try await client.send("PUT", "/api/dishes/\(id)", body: draft)
    }

    func deleteDish(id: String) async throws -> ShoppingBoard {
        try await client.delete("/api/dishes/\(id)")
    }

    /// Alle Zutaten des Gerichts auf die Liste.
    func addDish(id: String) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/dishes/\(id)/add", body: Empty(), queueWhenOffline: true)
    }

    // MARK: Regeln

    func createRule(_ draft: ShoppingRuleDraft) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/recurring", body: draft)
    }

    func updateRule(id: String, draft: ShoppingRuleDraft) async throws -> ShoppingBoard {
        try await client.send("PUT", "/api/recurring/\(id)", body: draft)
    }

    func deleteRule(id: String) async throws -> ShoppingBoard {
        try await client.delete("/api/recurring/\(id)")
    }

    private struct Empty: Encodable {}
}
