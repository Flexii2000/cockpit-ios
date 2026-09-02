import Foundation

/// Naehrwerte. Je nach Zusammenhang pro 100 g oder als Tagessumme - der Typ
/// ist derselbe, die Bedeutung steht am Feld, das ihn haelt.
struct Nutrients: Codable, Equatable, Sendable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    static let zero = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)

    /// Was eine Menge davon beitraegt - die Werte gelten je 100 g.
    func scaled(gramsOf grams: Double) -> Nutrients {
        let factor = grams / 100
        return Nutrients(kcal: kcal * factor, proteinG: proteinG * factor,
                         carbsG: carbsG * factor, fatG: fatG * factor)
    }
}

/// Reihenfolge wie der Tag verlaeuft, nicht alphabetisch.
enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case dinner = "DINNER"
    case snack = "SNACK"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch:     "Mittagessen"
        case .dinner:    "Abendessen"
        case .snack:     "Snacks"
        }
    }
}

struct Dish: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let per100g: Nutrients
    let portionG: Double?
    let lastUsedOn: CalendarDate?
}

struct FoodEntry: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let date: CalendarDate
    let dishId: String?
    let name: String
    let grams: Double
    let per100g: Nutrients?
    /// `nil` bei Eintraegen aus der Zeit vor der Mahlzeiten-Aufteilung. Die
    /// nachtraeglich einzusortieren hiesse, eine Vermutung wie eine Angabe
    /// aussehen zu lassen - sie stehen deshalb in einem eigenen Abschnitt.
    let meal: Meal?
    let createdAt: Date

    /// Was dieser Eintrag zum Tag beitraegt.
    var total: Nutrients { per100g?.scaled(gramsOf: grams) ?? .zero }
}

struct DaySummary: Decodable, Sendable {
    let date: CalendarDate
    let targets: Nutrients
    let consumed: Nutrients
    let remaining: Nutrients
    let entries: [FoodEntry]
    /// kcal-Ziel je Mahlzeit. Als `[String: Double]` gelesen und erst danach
    /// zugeordnet: ein Dictionary mit Enum-Schluessel laesst sich zwar
    /// decodieren, aber nur ueber `CodingKeyRepresentable` - der Umweg ist
    /// mehr Zeremonie als der Zweifelsfall wert.
    private let mealTargets: [String: Double]

    var targetsByMeal: [Meal: Double] {
        Dictionary(uniqueKeysWithValues: mealTargets.compactMap { key, value in
            Meal(rawValue: key).map { ($0, value) }
        })
    }
}

struct DayTotal: Decodable, Identifiable, Sendable {
    let date: CalendarDate
    let consumed: Nutrients

    var id: CalendarDate { date }
}

struct Features: Decodable, Sendable {
    let quickCapture: Bool
}

struct DishRequest: Encodable, Sendable {
    let name: String
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let portionG: Double?
}

struct NewEntryRequest: Encodable, Sendable {
    let date: CalendarDate
    let dishId: String?
    let dish: DishRequest?
    let grams: Double
    let meal: Meal?
}

struct TargetsRequest: Encodable, Sendable {
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let mealShares: [String: Double]?
}

struct QuickCaptureRequest: Encodable, Sendable {
    let date: CalendarDate
    let text: String
    let meal: Meal?
}

/// Der Auftrag an die Schnellerfassung. Sie laeuft als Claude-Session auf dem
/// Server und dauert bis zu einer Minute - deshalb ein Auftrag mit Kennung
/// statt einer Antwort (siehe docs/BACKENDS.md).
struct QuickCaptureJob: Decodable, Sendable {
    let id: String
    let status: String
    let preview: QuickCapturePreview?
    let error: String?
    let elapsedSeconds: Int

    static let running = "running"
    static let done = "done"
    static let failed = "failed"

    var isRunning: Bool { status == Self.running }
}

/// Der Vorschlag. Eingetragen wird er erst nach dem Bestaetigen: eine
/// geschaetzte Zahl, die ungefragt im Tagebuch landet, sieht dort hinterher
/// genauso aus wie eine abgelesene.
struct QuickCapturePreview: Decodable, Sendable {
    let known: Bool
    let dishId: String?
    let name: String
    let per100g: Nutrients
    let portionG: Double?
    let grams: Double
    let meal: Meal?
    /// Je Wert, woher er stammt - der Agent unterscheidet Nachgeschlagenes
    /// von Geschaetztem.
    let valueSources: [String: String]
    let note: String?
}

/// Die Push-Kennung dieses Geraets, wie der Server sie erwartet.
struct DeviceRegistration: Encodable, Sendable {
    let token: String
}
