import Foundation

/// Die Endpunkte des Einkaufslisten-Dienstes.
///
/// Zugang ueber den Einkaufs-Cookie, den `Access.applyCookies()` fuer den
/// Pfad `/shopping-list` setzt - der Dienst nimmt denselben Cookie wie der
/// Browser nach `/shopping-list/setup?token=…`.
///
/// Was im Laden passiert - Haken, neuer Eintrag, Gericht auf die Liste -,
/// geht nicht hier entlang, sondern durch die Warteschlange (`ShoppingChange`,
/// `PendingChanges`): sofort zu sehen, spaeter geschickt. Gerichte und Regeln
/// pflegen ist Schreibtischarbeit - das darf scheitern und es sagen.
struct ShoppingAPI: Sendable {

    private let client: APIClient

    init(timeout: TimeInterval = 30) {
        client = APIClient(backend: .shopping, cookie: nil, timeout: timeout)
    }

    func board() async throws -> ShoppingBoard {
        try await client.get("/api/board")
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
}
