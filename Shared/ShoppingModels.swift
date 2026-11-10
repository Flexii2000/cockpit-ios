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
    /// Als `#RRGGBB` - dieselbe Farbe im Web und in der App.
    var color: String?

    var id: String { key }

    /// Die Farbe als Zahl fuer `Color(hex:)`; `nil`, wenn der Dienst keine
    /// schickt oder sie nicht wie `#RRGGBB` aussieht.
    var colorValue: UInt32? {
        guard let color, color.hasPrefix("#"), color.count == 7 else { return nil }
        return UInt32(color.dropFirst(), radix: 16)
    }
}

/// Ein Eintrag auf der Liste. `var`, nicht `let`: was wartet, legt die App
/// ueber den Stand des Dienstes (`ShoppingOverlay`).
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
}

struct ShoppingIngredient: Codable, Equatable, Hashable, Sendable {
    var name: String
    var quantity: String?
    /// Hat man meist da (Salz, Oel): beim „Auf die Liste“ nicht vorgewaehlt. In
    /// Staenden von vor den Rezepten fehlt das Feld und heisst nein; beim Senden
    /// heisst „fehlt“: der Dienst laesst der gleichnamigen Zutat ihr Kennzeichen.
    var pantry: Bool? = nil

    var isPantry: Bool { pantry == true }
}

/// Naehrwerte eines Rezepts **je Portion** - alle vier oder keiner. Der
/// Kalorienzaehler rechnet je 100 g; umgerechnet wird erst beim Kochen, im Dienst.
struct ShoppingNutrition: Codable, Equatable, Hashable, Sendable {
    var kcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    /// Ohne einen einzigen Wert - so geht „keine Naehrwerte mehr“ an den Dienst (`{}`).
    static let empty = ShoppingNutrition()

    var isComplete: Bool { kcal != nil && proteinG != nil && carbsG != nil && fatG != nil }
}

/// Ein Rezept: eine Zutatenliste, die als Ganzes auf die Einkaufsliste geht - und
/// seit November 2026 auf Wunsch Portionen, Schritte und Naehrwerte. Beim Dienst und
/// im Brett heisst es weiter `dishes`; aeltere App-Staende lesen genau das.
///
/// Alles Neue darf fehlen: ein Gericht von frueher ist ein Rezept ohne diese Felder,
/// und ein Brett aus dem Offline-Stand von vor dem Update muss weiter lesbar sein.
struct ShoppingDish: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var ingredients: [ShoppingIngredient]
    var createdAt: Date
    /// Fuer wie viele Portionen die Mengen gelten; ohne laesst sich nicht umrechnen.
    var portions: Int? = nil
    var minutes: Int? = nil
    var steps: [String]? = nil
    /// Je Portion.
    var nutrition: ShoppingNutrition? = nil
    var gramsPerPortion: Double? = nil
    /// `"chat"`, wenn es aus einem Entwurf des Rezept-Chats gespeichert wurde.
    var source: String? = nil
    var createdBy: String? = nil

    var stepList: [String] { steps ?? [] }

    /// Ob sich die Mengen umrechnen lassen.
    var basePortions: Int? {
        guard let portions, portions > 0 else { return nil }
        return portions
    }

    /// Ein Gericht wie vor den Rezepten: nur Name und Zutaten. Es behaelt in der
    /// Liste den einen Tipp „Auf die Liste“ - es gibt dort nichts zu waehlen.
    var isPlain: Bool {
        basePortions == nil && minutes == nil && stepList.isEmpty && nutrition == nil
            && !ingredients.contains(where: \.isPantry)
    }

    /// Die Zutaten fuer so viele Portionen - gerechnet wie beim Dienst
    /// (`GET dishes/{id}/scaled`), damit es auch ohne Netz stimmt. Ohne Angabe oder
    /// ohne Portionen am Rezept die gespeicherten Mengen.
    func ingredients(for portions: Int?) -> [ShoppingScaledIngredient] {
        ingredients.map { ingredient in
            guard let portions, let base = basePortions else {
                return ShoppingScaledIngredient(name: ingredient.name, quantity: ingredient.quantity,
                                                pantry: ingredient.isPantry, scaled: true)
            }
            let result = ShoppingQuantity.scale(ingredient.quantity, portions: portions, base: base)
            return ShoppingScaledIngredient(name: ingredient.name, quantity: result.quantity,
                                            pantry: ingredient.isPantry, scaled: result.scaled)
        }
    }
}

/// Eine Zutat mit umgerechneter Menge. `scaled` ist falsch, wenn sich die Menge
/// nicht lesen liess („eine Handvoll“) und deshalb dasteht, wie sie gespeichert ist -
/// die Oberflaeche zeigt sie dann blasser.
struct ShoppingScaledIngredient: Equatable, Sendable {
    var name: String
    var quantity: String?
    var pantry: Bool
    var scaled: Bool
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
/// der Dienst zu und lernt nichts Falsches. `id` nur beim Anlegen: die
/// Kennung, die die App dem neuen Eintrag gibt (kleingeschriebene UUID).
struct ShoppingItemDraft: Encodable, Sendable {
    let name: String
    let quantity: String?
    let note: String?
    let category: String?
    var id: String? = nil
}

/// Anlegen und Aendern eines Rezepts. Beim Aendern gilt beim Dienst: **fehlt ein Feld,
/// bleibt es** - der leere Wert loescht (`steps: []`, `portions: 0`, `minutes: 0`,
/// `gramsPerPortion: 0`, `nutrition: {}`). `nil` hier heisst also „nicht anfassen“.
struct ShoppingDishDraft: Encodable, Equatable, Sendable {
    let name: String
    let ingredients: [ShoppingIngredient]
    var portions: Int? = nil
    var minutes: Int? = nil
    var steps: [String]? = nil
    var nutrition: ShoppingNutrition? = nil
    var gramsPerPortion: Double? = nil
}

// MARK: - Rezept-Chat und Kochen

/// Der Rezept-Chat einer Person: das Gespraech und ob gerade eine Antwort entsteht.
/// Derselbe Abruf ist auch die Nachfrage, solange `job` laeuft.
struct ShoppingChat: Decodable, Equatable, Sendable {
    /// Ob die Person den Chat benutzen kann (freigeschaltet, Agent eingerichtet) -
    /// sonst zeigt die App ihn gar nicht.
    var available: Bool
    var messages: [ShoppingChatMessage]
    var job: Job?

    struct Job: Decodable, Equatable, Sendable {
        /// `running` oder `failed`; Unbekanntes zaehlt als keins von beiden.
        var status: String
        var elapsedSeconds: Int?
        /// Nur bei `failed`: ein Satz vom Dienst.
        var error: String?

        var isRunning: Bool { status == "running" }
        var isFailed: Bool { status == "failed" }
    }

    private enum CodingKeys: String, CodingKey { case available, messages, job }

    init(available: Bool, messages: [ShoppingChatMessage], job: Job? = nil) {
        self.available = available
        self.messages = messages
        self.job = job
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        messages = try container.decodeIfPresent([ShoppingChatMessage].self, forKey: .messages) ?? []
        job = try container.decodeIfPresent(Job.self, forKey: .job)
    }

    /// Die letzte eigene Nachricht, auf die keine Antwort folgte - nach einem
    /// Fehlschlag oder einem Neustart des Dienstes. Dieselbe Kennung noch einmal
    /// fordert beim Dienst nur die Antwort neu an.
    var unanswered: ShoppingChatMessage? {
        guard job?.isRunning != true, let last = messages.last, last.isMine else { return nil }
        return last
    }
}

struct ShoppingChatMessage: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    /// `user` oder `assistant`.
    var role: String
    var text: String
    var at: Date
    /// Der Rezeptvorschlag an einer Antwort.
    var draft: ShoppingRecipeDraft?
    /// Das Rezept, das aus dem Entwurf gespeichert wurde.
    var savedDishId: String?

    var isMine: Bool { role == "user" }

    private enum CodingKeys: String, CodingKey { case id, role, text, at, draft, savedDishId }

    init(id: String, role: String, text: String, at: Date, draft: ShoppingRecipeDraft? = nil,
         savedDishId: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.at = at
        self.draft = draft
        self.savedDishId = savedDishId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        at = try container.decode(Date.self, forKey: .at)
        draft = try container.decodeIfPresent(ShoppingRecipeDraft.self, forKey: .draft)
        savedDishId = try container.decodeIfPresent(String.self, forKey: .savedDishId)
    }
}

/// Ein Rezept, das der Chat vorgeschlagen hat - in der Form, in der es gespeichert
/// wuerde: Mengen als Text („250 g“), Naehrwerte je Portion.
struct ShoppingRecipeDraft: Decodable, Equatable, Sendable {
    var name: String
    var portions: Int?
    var minutes: Int?
    var ingredients: [ShoppingIngredient]
    var steps: [String]
    var nutrition: ShoppingNutrition?
    var gramsPerPortion: Double?

    private enum CodingKeys: String, CodingKey {
        case name, portions, minutes, ingredients, steps, nutrition, gramsPerPortion
    }

    init(name: String, portions: Int? = nil, minutes: Int? = nil, ingredients: [ShoppingIngredient] = [],
         steps: [String] = [], nutrition: ShoppingNutrition? = nil, gramsPerPortion: Double? = nil) {
        self.name = name
        self.portions = portions
        self.minutes = minutes
        self.ingredients = ingredients
        self.steps = steps
        self.nutrition = nutrition
        self.gramsPerPortion = gramsPerPortion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        portions = try container.decodeIfPresent(Int.self, forKey: .portions)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        ingredients = try container.decodeIfPresent([ShoppingIngredient].self, forKey: .ingredients) ?? []
        steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
        nutrition = try container.decodeIfPresent(ShoppingNutrition.self, forKey: .nutrition)
        gramsPerPortion = try container.decodeIfPresent(Double.self, forKey: .gramsPerPortion)
    }
}

/// Was „Kochen“ im Kalorienzaehler bewirkt hat. Kommt auch dann als Erfolg, wenn es
/// bei einer Person nicht geklappt hat - kochen kann man trotzdem.
struct ShoppingCookResult: Decodable, Equatable, Sendable {
    var dishId: String
    /// `nil`, wenn der Kalorienzaehler gefragt wurde; sonst `no-nutrition` (das
    /// Rezept hat keine Naehrwerte) oder `not-configured`.
    var reason: String?
    /// Je Person mit Healthy-Zugang, was aus dem Gericht wurde.
    var healthy: [Person]

    struct Person: Decodable, Equatable, Identifiable, Sendable {
        var person: String
        /// `created`, `updated`, `unchanged`, `rejected` oder `failed`.
        var status: String
        var message: String?

        var id: String { person }
        /// Das Gericht steht bei der Person - neu, aufgefrischt oder schon gleich.
        var isDone: Bool { ["created", "updated", "unchanged"].contains(status) }
    }

    private enum CodingKeys: String, CodingKey { case dishId, reason, healthy }

    init(dishId: String, reason: String? = nil, healthy: [Person] = []) {
        self.dishId = dishId
        self.reason = reason
        self.healthy = healthy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dishId = try container.decodeIfPresent(String.self, forKey: .dishId) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        healthy = try container.decodeIfPresent([Person].self, forKey: .healthy) ?? []
    }
}

/// Eine neue Nachricht im Rezept-Chat. `id` vergibt die App (kleingeschriebene UUID):
/// dieselbe noch einmal haengt nichts an.
struct ShoppingChatSend: Encodable, Sendable {
    let text: String
    let id: String
}

/// `nextAt` als ISO-Datum (`yyyy-MM-dd`), wie der Dienst es liest.
struct ShoppingRuleDraft: Encodable, Sendable {
    let name: String
    let quantity: String?
    let everyDays: Int
    let nextAt: String?
}
