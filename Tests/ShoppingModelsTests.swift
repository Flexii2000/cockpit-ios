import Foundation
import Testing
@testable import Healthy

/// Was der Einkaufslisten-Dienst schickt, so wie die App es liest - vor und nach
/// den Rezepten. Die Antworten sind die des Dienstes (`../shopping`, 2026-11-10),
/// gekuerzt.
struct ShoppingModelsTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Brett

    /// Ein Brett, wie es vor den Rezepten kam - und wie es im Offline-Stand einer
    /// App liegen kann, die gerade aktualisiert wurde.
    private static let boardBeforeRecipes = #"""
        {"me":"felix",
         "categories":[{"key":"produce","label":"Obst & Gemüse","emoji":"🥦","symbol":"carrot","color":"#34A853"}],
         "items":[{"id":"i-1","name":"Zwiebeln","quantity":"2 Stk","note":"Suppe","category":"produce",
                   "addedAt":"2026-10-12T08:00:00.123456Z","addedBy":"joana","checkedAt":null,"checkedBy":null,
                   "dishId":"d-1","ruleId":null}],
         "dishes":[{"id":"d-1","name":"Suppe","createdAt":"2026-10-01T10:00:00Z",
                    "ingredients":[{"name":"Zwiebeln","quantity":"2 Stk"},{"name":"Lauch","quantity":null}]}],
         "recurring":[]}
        """#

    private static let boardWithRecipes = #"""
        {"me":"felix","categories":[],"items":[],"recurring":[],
         "dishes":[
          {"id":"d-2","name":"Brot","ingredients":[{"name":"Mehl","quantity":"500 g","pantry":true}],
           "createdAt":"2026-11-10T12:42:36.542456Z","portions":null,"minutes":null,"steps":[],"nutrition":null,
           "gramsPerPortion":null,"source":null,"createdBy":"felix"},
          {"id":"d-3","name":"Ofenpasta","createdAt":"2026-11-10T12:42:40.677642Z",
           "ingredients":[{"name":"Penne","quantity":"250 g","pantry":false},
                          {"name":"Olivenöl","quantity":"3 EL","pantry":true},
                          {"name":"Salz","quantity":null,"pantry":true}],
           "portions":2,"minutes":35,"steps":["Den Ofen vorheizen.","Die Penne kochen."],
           "nutrition":{"kcal":860.0,"proteinG":33.0,"carbsG":98.0,"fatG":36.0},"gramsPerPortion":480.0,
           "source":"chat","createdBy":"joana"},
          {"id":"d-1","name":"Suppe","ingredients":[{"name":"Zwiebeln","quantity":"2 Stk","pantry":false}],
           "createdAt":"2026-10-01T10:00:00Z","portions":null,"minutes":null,"steps":[],"nutrition":null,
           "gramsPerPortion":null,"source":null,"createdBy":null}]}
        """#

    @Test func aBoardFromBeforeRecipesStillReads() throws {
        let board = try decode(ShoppingBoard.self, Self.boardBeforeRecipes)
        let dish = try #require(board.dishes.first)
        #expect(dish.name == "Suppe")
        #expect(dish.ingredients == [ShoppingIngredient(name: "Zwiebeln", quantity: "2 Stk"),
                                     ShoppingIngredient(name: "Lauch", quantity: nil)])
        #expect(dish.portions == nil)
        #expect(dish.stepList.isEmpty)
        #expect(dish.nutrition == nil)
        #expect(dish.isPlain, "ein Gericht von frueher behaelt den einen Tipp")
        #expect(board.items.first?.dishId == "d-1")
    }

    @Test func aBoardWithRecipesReadsEverything() throws {
        let board = try decode(ShoppingBoard.self, Self.boardWithRecipes)
        let recipe = try #require(board.dishes.first { $0.id == "d-3" })
        #expect(recipe.basePortions == 2)
        #expect(recipe.minutes == 35)
        #expect(recipe.stepList == ["Den Ofen vorheizen.", "Die Penne kochen."])
        #expect(recipe.nutrition == ShoppingNutrition(kcal: 860, proteinG: 33, carbsG: 98, fatG: 36))
        #expect(recipe.nutrition?.isComplete == true)
        #expect(recipe.gramsPerPortion == 480)
        #expect(recipe.source == "chat")
        #expect(recipe.createdBy == "joana")
        #expect(recipe.ingredients.map(\.isPantry) == [false, true, true])
        #expect(!recipe.isPlain)
    }

    @Test func onlyADishWithoutAnythingNewIsPlain() throws {
        let board = try decode(ShoppingBoard.self, Self.boardWithRecipes)
        let bread = try #require(board.dishes.first { $0.id == "d-2" })
        let soup = try #require(board.dishes.first { $0.id == "d-1" })
        // Kein Rezept im engeren Sinn, aber mit Vorrat: da gibt es etwas zu waehlen.
        #expect(!bread.isPlain)
        #expect(soup.isPlain)
    }

    // MARK: - Was die App schickt

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: APIClient.encoder().encode(value)) as? [String: Any])
    }

    @Test func aDraftLeavesOutWhatItDoesNotTouch() throws {
        // Fehlt ein Feld, laesst der Dienst es stehen - so darf ein Rumpf nur aus
        // Name und Zutaten Schritte und Naehrwerte nicht loeschen.
        let body = try json(ShoppingDishDraft(name: "Suppe", ingredients: [ShoppingIngredient(name: "Lauch", quantity: "1 Stange")]))
        #expect(Set(body.keys) == ["name", "ingredients"])
        let ingredient = try #require((body["ingredients"] as? [[String: Any]])?.first)
        #expect(Set(ingredient.keys) == ["name", "quantity"], "ohne `pantry` behaelt die Zutat ihr Kennzeichen")
    }

    @Test func aDraftSendsTheEmptyValueToClear() throws {
        let body = try json(ShoppingDishDraft(name: "Suppe", ingredients: [ShoppingIngredient(name: "Salz", quantity: nil, pantry: true)],
                                              portions: 0, minutes: 0, steps: [], nutrition: ShoppingNutrition.empty,
                                              gramsPerPortion: 0))
        #expect(body["portions"] as? Int == 0)
        #expect(body["minutes"] as? Int == 0)
        #expect((body["steps"] as? [String])?.isEmpty == true)
        #expect((body["nutrition"] as? [String: Any])?.isEmpty == true, "`{}` heisst: keine Naehrwerte mehr")
        #expect(body["gramsPerPortion"] as? Double == 0)
        let ingredient = try #require((body["ingredients"] as? [[String: Any]])?.first)
        #expect(ingredient["pantry"] as? Bool == true)
    }

    @Test func aChatMessageCarriesItsIdAndText() throws {
        let body = try json(ShoppingChatSend(text: "Etwas mit Reis", id: "11111111-1111-4111-8111-111111111111"))
        #expect(body["text"] as? String == "Etwas mit Reis")
        #expect(body["id"] as? String == "11111111-1111-4111-8111-111111111111")
    }

    // MARK: - Rezept-Chat

    private static let chatRunning = #"""
        {"available":true,"messages":[{"id":"m-1","role":"user","text":"Etwas mit Pasta und Feta",
          "at":"2026-11-10T12:42:36.555212Z","draft":null,"savedDishId":null}],
         "job":{"status":"running","elapsedSeconds":3}}
        """#

    private static let chatWithDraft = #"""
        {"available":true,"messages":[
          {"id":"m-1","role":"user","text":"Etwas mit Pasta und Feta","at":"2026-11-10T12:42:36.555212Z",
           "draft":null,"savedDishId":null},
          {"id":"m-2","role":"assistant","text":"Wie wäre es mit einer Ofenpasta?","at":"2026-11-10T12:42:38.618239Z",
           "draft":{"name":"Ofenpasta","portions":2,"minutes":35,
                    "ingredients":[{"name":"Penne","quantity":"250 g","pantry":false},
                                   {"name":"Salz","quantity":null,"pantry":true}],
                    "steps":["Den Ofen vorheizen."],
                    "nutrition":{"kcal":860.0,"proteinG":33.0,"carbsG":98.0,"fatG":36.0},"gramsPerPortion":480.0},
           "savedDishId":"d-3"}],
         "job":null}
        """#

    @Test func aRunningChatReads() throws {
        let chat = try decode(ShoppingChat.self, Self.chatRunning)
        #expect(chat.available)
        #expect(chat.messages.count == 1)
        #expect(chat.messages[0].isMine)
        #expect(chat.job?.isRunning == true)
        #expect(chat.job?.elapsedSeconds == 3)
        #expect(chat.unanswered == nil, "solange die Antwort entsteht, ist nichts unbeantwortet")
    }

    @Test func anAnswerCarriesItsDraft() throws {
        let chat = try decode(ShoppingChat.self, Self.chatWithDraft)
        #expect(chat.job == nil)
        let answer = try #require(chat.messages.last)
        #expect(!answer.isMine)
        #expect(answer.savedDishId == "d-3")
        let draft = try #require(answer.draft)
        #expect(draft.name == "Ofenpasta")
        #expect(draft.portions == 2)
        #expect(draft.ingredients.map(\.isPantry) == [false, true])
        #expect(draft.steps == ["Den Ofen vorheizen."])
        #expect(draft.nutrition?.kcal == 860)
        #expect(draft.gramsPerPortion == 480)
    }

    @Test func aFailedOrUnknownJobAndMissingFieldsRead() throws {
        let failed = try decode(ShoppingChat.self, #"""
            {"available":true,"messages":[{"id":"m-1","role":"user","text":"Hallo","at":"2026-11-10T12:00:00Z"}],
             "job":{"status":"failed","error":"Claude konnte nicht antworten."}}
            """#)
        #expect(failed.job?.isFailed == true)
        #expect(failed.job?.error == "Claude konnte nicht antworten.")
        #expect(failed.messages[0].draft == nil)

        // Ein Stand, den diese App noch nicht kennt, bricht nichts.
        let unknown = try decode(ShoppingChat.self, #"{"available":true,"messages":[],"job":{"status":"queued"}}"#)
        #expect(unknown.job?.isRunning == false)
        #expect(unknown.job?.isFailed == false)

        let off = try decode(ShoppingChat.self, #"{"available":false,"messages":[],"job":null}"#)
        #expect(!off.available)

        let sparse = try decode(ShoppingRecipeDraft.self, #"{"name":"Rezept A"}"#)
        #expect(sparse.ingredients.isEmpty)
        #expect(sparse.steps.isEmpty)
    }

    // MARK: - Was der Chat zeigt

    private func message(_ id: String, mine: Bool, text: String = "Text") -> ShoppingChatMessage {
        ShoppingChatMessage(id: id, role: mine ? "user" : "assistant", text: text,
                            at: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func theOwnMessageShowsBeforeTheServiceHasIt() {
        let pending = ShoppingChatPending(id: "m-2", text: "Etwas mit Reis")
        let chat = ShoppingChat(available: true, messages: [message("m-0", mine: true), message("m-1", mine: false)])
        let rows = ShoppingChatTimeline.rows(chat: chat, pending: pending, sendError: nil, stalled: false)
        #expect(rows.map(\.id) == ["m-0", "m-1", "m-2", "typing"])
        #expect(rows[2] == .sending(pending))
        #expect(ShoppingChatTimeline.isBusy(chat: chat, pending: pending, sendError: nil, stalled: false))
    }

    @Test func aConfirmedMessageIsNotShownTwice() {
        let pending = ShoppingChatPending(id: "m-1", text: "Etwas mit Reis")
        let chat = ShoppingChat(available: true, messages: [message("m-1", mine: true)],
                                job: .init(status: "running", elapsedSeconds: 1, error: nil))
        let rows = ShoppingChatTimeline.rows(chat: chat, pending: pending, sendError: nil, stalled: false)
        #expect(rows.map(\.id) == ["m-1", "typing"])
    }

    @Test func aRunningAnswerShowsTyping() {
        let chat = ShoppingChat(available: true, messages: [message("m-1", mine: true)],
                                job: .init(status: "running", elapsedSeconds: 12, error: nil))
        #expect(ShoppingChatTimeline.rows(chat: chat, pending: nil, sendError: nil, stalled: false).last == .typing)
        #expect(ShoppingChatTimeline.isBusy(chat: chat, pending: nil, sendError: nil, stalled: false))
        // Nach 150 s ohne Ende: nicht ewig drehen, sondern noch einmal anbieten.
        #expect(ShoppingChatTimeline.rows(chat: chat, pending: nil, sendError: nil, stalled: true).last == .failed(message: nil))
        #expect(!ShoppingChatTimeline.isBusy(chat: chat, pending: nil, sendError: nil, stalled: true))
    }

    @Test func aFailedAnswerOffersToSendAgain() {
        let failed = ShoppingChat(available: true, messages: [message("m-1", mine: true, text: "Etwas mit Reis")],
                                  job: .init(status: "failed", elapsedSeconds: nil, error: "Claude konnte nicht antworten."))
        #expect(ShoppingChatTimeline.rows(chat: failed, pending: nil, sendError: nil, stalled: false).last
                == .failed(message: "Claude konnte nicht antworten."))
        #expect(ShoppingChatTimeline.retry(chat: failed, pending: nil) == ShoppingChatPending(id: "m-1", text: "Etwas mit Reis"),
                "dieselbe Kennung - der Dienst fordert nur die Antwort neu an")

        // Der Dienst lief neu: die Frage steht ohne Antwort da, und nichts laeuft.
        let orphan = ShoppingChat(available: true, messages: [message("m-0", mine: false), message("m-1", mine: true)])
        #expect(orphan.unanswered?.id == "m-1")
        #expect(ShoppingChatTimeline.rows(chat: orphan, pending: nil, sendError: nil, stalled: false).last == .failed(message: nil))

        let answered = ShoppingChat(available: true, messages: [message("m-1", mine: true), message("m-2", mine: false)])
        #expect(ShoppingChatTimeline.rows(chat: answered, pending: nil, sendError: nil, stalled: false).map(\.id) == ["m-1", "m-2"])
    }

    @Test func aMessageThatDidNotGoOutStaysWithItsReason() {
        let pending = ShoppingChatPending(id: "m-2", text: "Etwas mit Reis")
        let chat = ShoppingChat(available: true, messages: [message("m-1", mine: false)])
        let rows = ShoppingChatTimeline.rows(chat: chat, pending: pending, sendError: "Kein Netz.", stalled: false)
        #expect(rows.map(\.id) == ["m-1", "m-2", "failed"])
        #expect(rows.last == .failed(message: "Kein Netz."))
        #expect(!ShoppingChatTimeline.isBusy(chat: chat, pending: pending, sendError: "Kein Netz.", stalled: false))
        #expect(ShoppingChatTimeline.retry(chat: chat, pending: pending) == pending)
    }

    @Test func withoutAnythingThereIsNothingToShow() {
        #expect(ShoppingChatTimeline.rows(chat: nil, pending: nil, sendError: nil, stalled: false).isEmpty)
        #expect(ShoppingChatTimeline.retry(chat: nil, pending: nil) == nil)
    }

    // MARK: - Kochen

    @Test func theCookResultSaysWhoHasTheDish() throws {
        let result = try decode(ShoppingCookResult.self, #"""
            {"dishId":"d-3","reason":null,"healthy":[
              {"person":"felix","status":"created","message":null},
              {"person":"joana","status":"failed","message":"Kalorienzähler nicht erreichbar"}]}
            """#)
        #expect(result.reason == nil)
        #expect(result.healthy.map(\.isDone) == [true, false])
        #expect(result.healthy[1].message == "Kalorienzähler nicht erreichbar")

        for status in ["created", "updated", "unchanged"] {
            #expect(ShoppingCookResult.Person(person: "p", status: status, message: nil).isDone)
        }
        #expect(!ShoppingCookResult.Person(person: "p", status: "rejected", message: "zu viel").isDone)

        let none = try decode(ShoppingCookResult.self, #"{"dishId":"d-1","reason":"no-nutrition","healthy":[]}"#)
        #expect(none.reason == "no-nutrition")
        #expect(none.healthy.isEmpty)
    }
}
