import Foundation

/// Ein Eintrag im Kalorienzaehler, sofort gezeigt und spaeter geschickt (Runde 4
/// der Aenderungen vom 12.10.). Neue Eintraege bekommen ihre Kennung von der App:
/// der Dienst uebernimmt sie, dieselbe zweimal legt nichts an - und ein Eintrag,
/// der noch wartet, laesst sich schon berichtigen oder loeschen.
enum FoodChange: Codable, Equatable, Sendable {
    /// `name` und `per100g` nur fuer die Anzeige, bis der Dienst antwortet.
    case add(id: String, date: CalendarDate, meal: Meal?, grams: Double, dishId: String?, dish: DishRequest?,
             name: String, per100g: Nutrients?, at: Date)
    /// Menge, Mahlzeit, Tag - das Gericht bleibt (wie `PUT /api/food/entries/{id}`).
    case update(id: String, grams: Double, meal: Meal?, date: CalendarDate?)
    case delete(id: String)

    var id: String {
        switch self {
        case .add(let id, _, _, _, _, _, _, _, _), .update(let id, _, _, _), .delete(let id): id
        }
    }

    var target: String? { id }

    var role: PendingRole {
        switch self {
        case .add: .create
        case .update: .edit
        case .delete: .delete
        }
    }

    var request: PendingRequest {
        switch self {
        case .add(let id, let date, let meal, let grams, let dishId, let dish, _, _, _):
            PendingRequest(method: "POST", path: "/api/food/entries",
                           body: Self.json(NewEntryRequest(date: date, dishId: dishId, dish: dish, grams: grams,
                                                           meal: meal, id: id)))
        case .update(let id, let grams, let meal, let date):
            PendingRequest(method: "PUT", path: "/api/food/entries/\(id)",
                           body: Self.json(UpdateEntryRequest(grams: grams, meal: meal, date: date)))
        case .delete(let id):
            PendingRequest(method: "DELETE", path: "/api/food/entries/\(id)", notFoundMeansDone: true)
        }
    }

    /// Ein wartendes Anlegen mit einer spaeteren Berichtigung zusammengefasst.
    func folded(with change: FoodChange) -> FoodChange? {
        guard case .add(let id, let date, let meal, _, let dishId, let dish, let name, let per100g, let at) = self,
              case .update(let other, let grams, let newMeal, let newDate) = change, other == id else { return nil }
        return .add(id: id, date: newDate ?? date, meal: newMeal ?? meal, grams: grams, dishId: dishId, dish: dish,
                    name: name, per100g: per100g, at: at)
    }

    /// „„Skyr“ wurde nicht eingetragen: <Grund>“ - mit dem Grund des Dienstes.
    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        let name = "„\(label)“"
        if status == 404 {
            return PendingNotice(text: "\(name) gibt es nicht mehr.", isInfo: true)
        }
        return switch self {
        case .add: .error("\(name) wurde nicht eingetragen", message, status: status)
        case .update: .error("\(name) ließ sich nicht ändern", message, status: status)
        case .delete: .error("\(name) ließ sich nicht löschen", message, status: status)
        }
    }

    private static func json<T: Encodable>(_ value: T) -> Data? {
        try? APIClient.encoder().encode(value)
    }
}

/// Der Tag, wie die App ihn zeigt: der Stand des Dienstes und darueber, was wartet.
///
/// Die Summen sind dann **vorlaeufig** (Felix, 12.10.): die Zahl des Dienstes plus
/// die Differenz der wartenden Eintraege - je 100 g mal Menge, wie der Dienst
/// rechnet. Sonst rechnet die App nichts nach; nach dem Senden gilt wieder der Tag
/// des Dienstes.
enum FoodOverlay {

    /// - Parameter known: Eintraege anderer Tage, die die App schon kennt - fuer
    ///   einen, der auf diesen Tag wandert, solange das Berichtigen noch wartet.
    static func apply(_ changes: [FoodChange], to day: DaySummary, known: [FoodEntry] = []) -> DaySummary {
        guard !changes.isEmpty else { return day }
        var entries = day.entries
        var pool: [String: FoodEntry] = [:]
        for entry in known + day.entries { pool[entry.id] = entry }
        for change in changes {
            switch change {
            case .add(let id, let date, let meal, let grams, let dishId, _, let name, let per100g, let at):
                // Kam die Antwort schon, steht der Eintrag im Tag - dann nicht doppelt.
                let entry = pool[id] ?? FoodEntry(id: id, date: date, dishId: dishId, name: name, grams: grams,
                                                  per100g: per100g, meal: meal ?? .snack, createdAt: at)
                pool[id] = entry
                if entry.date == day.date, !entries.contains(where: { $0.id == id }) {
                    entries.append(entry)
                }
            case .update(let id, let grams, let meal, let date):
                guard let old = pool[id] else { continue }
                let changed = FoodEntry(id: old.id, date: date ?? old.date, dishId: old.dishId, name: old.name,
                                        grams: grams, per100g: old.per100g, meal: meal ?? old.meal,
                                        createdAt: old.createdAt)
                pool[id] = changed
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    if changed.date == day.date {
                        entries[index] = changed
                    } else {
                        entries.remove(at: index)
                    }
                } else if changed.date == day.date {
                    entries.append(changed)
                }
            case .delete(let id):
                entries.removeAll { $0.id == id }
                pool[id] = nil
            }
        }
        guard entries != day.entries else { return day }
        let before = day.entries.reduce(Nutrients.zero) { $0 + $1.total }
        let after = entries.reduce(Nutrients.zero) { $0 + $1.total }
        return day.replacing(entries: entries, consumed: day.consumed + (after - before))
    }

    /// Ob wartende Aenderungen den Tag veraendern - dann sind seine Summen vorlaeufig.
    static func isProvisional(_ changes: [FoodChange], day: DaySummary, known: [FoodEntry] = []) -> Bool {
        apply(changes, to: day, known: known).entries != day.entries
    }
}

/// Was die Kalorien-Kachel von der App braucht, solange Eintraege warten: die
/// wartenden Aenderungen (die Kachel legt sie selbst ueber den frisch geholten Tag)
/// und, fuer die Kachel ohne Netz, den Rest, den die App fuer heute zeigt.
///
/// Ueber die geteilte Keychain-Gruppe, die Healthy und die Kachel schon haben -
/// eine App-Gruppe braeuchte neue Provisionierung, und scheiterte die, ginge
/// gleich das Installieren schief.
enum PendingFoodMirror {

    static let changesKey = "pending_food_changes"
    static let todayKey = "pending_food_today"

    /// - Returns: ob sich etwas geaendert hat - nur dann muss die Kachel neu rechnen.
    @discardableResult
    static func saveChanges(_ changes: [FoodChange]) -> Bool {
        let text = changes.isEmpty ? nil : encode(changes)
        guard text != Keychain.read(changesKey) else { return false }
        if let text {
            Keychain.save(text, for: changesKey)
        } else {
            Keychain.delete(changesKey)
        }
        return true
    }

    static func loadChanges() -> [FoodChange] {
        Keychain.read(changesKey).flatMap { decode([FoodChange].self, $0) } ?? []
    }

    /// Nur ein vorlaeufiger Stand wird gemerkt - ohne Wartendes gilt der des Dienstes.
    static func saveToday(_ value: RemainingCalories?) {
        guard let value, value.provisional == true, let text = encode(value) else {
            Keychain.delete(todayKey)
            return
        }
        Keychain.save(text, for: todayKey)
    }

    static func loadToday() -> RemainingCalories? {
        Keychain.read(todayKey).flatMap { decode(RemainingCalories.self, $0) }
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? APIClient.encoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ text: String) -> T? {
        try? APIClient.decoder().decode(type, from: Data(text.utf8))
    }
}

/// Was der Kalorienzaehler beim Eintragen annimmt (`FoodService.addEntry`,
/// `upsertDish`) - geprueft, bevor etwas in die Warteschlange geht. Ohne Netz kaeme
/// eine Ablehnung erst beim Senden, vielleicht Stunden spaeter, und der Eintrag
/// verschwaende wieder; so bleibt „Eintragen“ aus, bis es passt.
enum FoodEntryRules {

    static let maxGrams: Double = 20_000
    static let maxKcalPer100g: Double = 1_000
    static let maxMacroPer100g: Double = 100
    static let maxNameLength = 80

    static func grams(_ grams: Double?) -> Bool {
        guard let grams, grams.isFinite else { return false }
        return grams > 0 && grams <= maxGrams
    }

    /// Ein neues Gericht braucht alle vier Werte je 100 g - der Dienst nimmt keins
    /// ohne Eiweiss, Kohlenhydrate oder Fett.
    static func dish(_ dish: DishRequest) -> Bool {
        let name = dish.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= maxNameLength else { return false }
        guard let kcal = dish.kcal, kcal.isFinite, (0...maxKcalPer100g).contains(kcal) else { return false }
        for value in [dish.proteinG, dish.carbsG, dish.fatG] {
            guard let value, value.isFinite, (0...maxMacroPer100g).contains(value) else { return false }
        }
        if let portion = dish.portionG, !grams(portion) { return false }
        return true
    }
}
