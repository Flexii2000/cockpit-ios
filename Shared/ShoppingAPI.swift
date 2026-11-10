import Foundation

/// Die Endpunkte des Einkaufslisten-Dienstes.
///
/// Zugang ueber den Einkaufs-Cookie, den `Access.applyCookies()` fuer den
/// Pfad `/shopping-list` setzt - der Dienst nimmt denselben Cookie wie der
/// Browser nach `/shopping-list/setup?token=…`.
///
/// Was im Laden passiert - Haken, neuer Eintrag, Rezept auf die Liste -,
/// geht nicht hier entlang, sondern durch die Warteschlange (`ShoppingChange`,
/// `PendingChanges`): sofort zu sehen, spaeter geschickt. Rezepte und Regeln
/// pflegen ist Schreibtischarbeit - das darf scheitern und es sagen. Dasselbe
/// gilt fuer den Rezept-Chat und fuers Kochen: beides braucht die Antwort jetzt.
struct ShoppingAPI: Sendable {

    private let client: APIClient

    init(timeout: TimeInterval = 30) {
        client = APIClient(backend: .shopping, cookie: nil, timeout: timeout)
    }

    func board() async throws -> ShoppingBoard {
        try await client.get("/api/board")
    }

    // MARK: Rezepte (beim Dienst weiter `dishes`)

    func createDish(_ draft: ShoppingDishDraft) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/dishes", body: draft)
    }

    func updateDish(id: String, draft: ShoppingDishDraft) async throws -> ShoppingBoard {
        try await client.send("PUT", "/api/dishes/\(id)", body: draft)
    }

    func deleteDish(id: String) async throws -> ShoppingBoard {
        try await client.delete("/api/dishes/\(id)")
    }

    /// „Kochen“: legt das Rezept bei allen, die Healthy haben, als Gericht in den
    /// Kalorienzaehler. Kein Rumpf, und die Antwort ist kein Brett - sie aendert an
    /// Liste und Rezepten nichts. Nie durch die Warteschlange: deren Antworten
    /// gelten als Brett und landen im Offline-Stand.
    func cook(dishId: String) async throws -> ShoppingCookResult {
        try await client.send("POST", "/api/dishes/\(dishId)/cook")
    }

    // MARK: Rezept-Chat

    /// Das eigene Gespraech - und die Nachfrage, solange eine Antwort entsteht.
    /// Ohne Offline-Stand: ein Gespraech von gestern mit „Antwort laeuft“ fuehrte
    /// ohne Netz nur in die Irre, und im Zwei-Sekunden-Takt braucht es keine Datei.
    func chat() async throws -> ShoppingChat {
        try await client.getFresh("/api/chat")
    }

    /// Antwortet sofort (202) mit dem Gespraech und `job.status == "running"`.
    func sendChat(text: String, id: String) async throws -> ShoppingChat {
        try await client.send("POST", "/api/chat/messages", body: ShoppingChatSend(text: text, id: id))
    }

    /// „Neu“: leert das Gespraech; eine Antwort, die noch unterwegs war, verwirft der Dienst.
    func resetChat() async throws -> ShoppingChat {
        try await client.delete("/api/chat")
    }

    /// Den Entwurf einer Antwort als Rezept speichern - die Antwort ist wieder das
    /// Brett. Ein zweiter Aufruf legt nichts mehr an.
    func saveDraft(messageId: String) async throws -> ShoppingBoard {
        try await client.send("POST", "/api/chat/drafts/\(messageId)/save")
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
