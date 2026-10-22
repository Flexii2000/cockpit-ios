import Foundation

/// Eine Verhaltensweise im Logbook - ja/nein, mit Einheit auch eine Menge
/// (Vertrag §4). Die Namen legt Felix in der App fest; im Repo stehen nur
/// Platzhalter.
struct Behavior: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// `nil`: nur ja/nein. Sonst die Einheit der Menge - nach dem Anlegen fest,
    /// sonst bedeuteten alte Zahlen etwas anderes als neue.
    let unit: String?
    let createdAt: Date?
    let archived: Bool
}

/// Ein Tag mit Antworten. Seit 12.10. zaehlt jede fuer sich: eine
/// Verhaltensweise ohne Wert ist an diesem Tag offen - „nicht beantwortet" ist
/// etwas anderes als „nein". Ein Tag ganz ohne Antwort fehlt.
struct LogbookDay: Codable, Equatable, Sendable {
    let date: CalendarDate
    let savedAt: Date?
    /// Verhaltensweise → 0 (nein), 1 (ja) bzw. die Menge; fehlend = offen.
    let values: [String: Double]
}

/// `GET /api/logbook`: alle Verhaltensweisen (auch archivierte) und die
/// gespeicherten Tage der Nachtragsfrist - genug fuer Karte und Eingabe.
struct LogbookOverview: Decodable, Equatable, Sendable {
    let behaviors: [Behavior]
    let backfillDays: Int
    let backfillFrom: CalendarDate
    let today: CalendarDate
    let days: [LogbookDay]

    var active: [Behavior] { behaviors.filter { !$0.archived } }
    var archived: [Behavior] { behaviors.filter(\.archived) }

    func day(_ date: CalendarDate) -> LogbookDay? {
        days.first { $0.date == date }
    }

    /// Mit einem Tag, wie ihn der Dienst nach dem Schreiben eines Werts schickt -
    /// ohne Werte faellt er weg, wie beim Dienst.
    func replacing(_ day: LogbookDay) -> LogbookOverview {
        var days = self.days.filter { $0.date != day.date }
        if !day.values.isEmpty { days.append(day) }
        return LogbookOverview(behaviors: behaviors, backfillDays: backfillDays, backfillFrom: backfillFrom,
                               today: today, days: days.sorted { $0.date < $1.date })
    }

    func with(behaviors: [Behavior]) -> LogbookOverview {
        LogbookOverview(behaviors: behaviors, backfillDays: backfillDays, backfillFrom: backfillFrom,
                        today: today, days: days)
    }
}

/// Woher ein Praediktor stammt.
enum PredictorSource: String, LenientEnum {
    case logbook = "LOGBOOK", cohabit = "COHABIT", healthy = "HEALTHY", unknown
}

/// Ja gegen nein, oder je Einheit einer Menge.
enum PredictorKind: String, LenientEnum {
    case binary = "BINARY", amount = "AMOUNT", unknown
}

/// `dose` ist der Effekt je Einheit nur an Ja-Tagen - die zweite Zeile einer
/// Verhaltensweise mit Einheit.
enum PredictorVariant: String, LenientEnum {
    case main = "MAIN", dose = "DOSE", unknown
}

enum PredictorStatus: String, LenientEnum {
    case ok = "OK"
    /// Zu wenig Tage, zu wenig ja oder nein, zu wenig Streuung.
    case tooFew = "TOO_FEW"
    /// Faellt mit dem Wochenende zusammen und laesst sich davon nicht trennen.
    case notSeparable = "NOT_SEPARABLE"
    case unknown
}

/// Was eine Verhaltensweise, ein Co-Habit oder ein Healthy-Wert mit der
/// Recovery des naechsten Morgens zu tun hat (Vertrag §4.1). Gerechnet im
/// Weight Tracker - Regression, Newey-West, Holm; hier wird nur gezeigt.
struct Predictor: Decodable, Identifiable, Equatable, Sendable {
    /// Eindeutig je Zeile - `LOGBOOK:<id>`, mit `:DOSE` fuer die zweite.
    let key: String
    let source: PredictorSource
    /// Die Kennung in ihrer Quelle; bei `DOSE` dieselbe wie bei `MAIN`.
    let sourceId: String
    let name: String
    let kind: PredictorKind
    let variant: PredictorVariant
    let unitLabel: String?
    /// Der Schritt, auf den sich der Effekt einer Menge bezieht (1.000
    /// Schritte, 100 kcal).
    let perUnit: Double
    /// In Prozentpunkten Recovery an einer typischen Nacht (Vertrag §4.1).
    let effect: Double?
    let ciLow: Double?
    let ciHigh: Double?
    let p: Double?
    /// Nach Holm ueber alle auswertbaren Zeilen - danach richten sich die Sterne.
    let pAdjusted: Double?
    /// Der Effekt auf die HRV in % (seit 22.10.) - ohne Intervall, ohne Sterne.
    let hrvEffectPercent: Double?
    /// Der Effekt auf den Puls im Schlaf in bpm (seit 22.10.).
    let sleepingHeartRateEffectBpm: Double?
    let nYes: Int?
    let nNo: Int?
    let n: Int
    let meanYes: Double?
    let meanNo: Double?
    let status: PredictorStatus

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, source, sourceId = "id", name, kind, variant, unitLabel, perUnit, effect, ciLow, ciHigh,
             p, pAdjusted, hrvEffectPercent, sleepingHeartRateEffectBpm, nYes, nNo, n, meanYes, meanNo, status
    }
}

/// `GET /api/logbook/insights?days=`: die Effekte eines Zeitraums.
struct LogbookInsights: Decodable, Equatable, Sendable {
    let days: Int
    let from: CalendarDate
    let to: CalendarDate
    /// Morgen mit Recovery-Score im Zeitraum.
    let nightsWithScore: Int
    /// `OK` oder `TOO_FEW_NIGHTS` (unter 14 Morgen mit Score).
    let outcomeStatus: String
    /// Ob coHabit und Kalorienzaehler antworteten (`OK`/`UNAVAILABLE`).
    let sources: [String: String]
    /// Vom Dienst sortiert: signifikant zuerst, dann nach |Effekt|, dann der Rest.
    let predictors: [Predictor]

    /// Ab so vielen Morgen mit Score rechnet der Dienst.
    static let requiredNights = 14

    var hasEnoughNights: Bool { outcomeStatus != "TOO_FEW_NIGHTS" }

    var evaluated: [Predictor] { predictors.filter { $0.status == .ok } }
    var notEvaluated: [Predictor] { predictors.filter { $0.status != .ok } }

    /// Die bis zu drei staerksten fuer die Karte im Dashboard - in der
    /// Reihenfolge des Dienstes, die schon „signifikant zuerst" ist.
    var strongest: [Predictor] { Array(evaluated.prefix(3)) }

    /// „coHabit", „Kalorienzähler" - wer nicht antwortete.
    var unavailableSources: [String] {
        let names = ["cohabit": "coHabit", "food": "Kalorienzähler"]
        return sources.filter { $0.value == "UNAVAILABLE" }.keys.sorted().map { names[$0] ?? $0 }
    }
}

/// Was die App an `POST /api/logbook/behaviors` schickt.
struct NewBehaviorRequest: Encodable, Sendable {
    let name: String
    let unit: String?
}

/// Was die App an `PUT /api/logbook/behaviors/{id}` schickt - die Einheit
/// bleibt, wie sie angelegt wurde. Was `nil` ist, fehlt im JSON.
struct BehaviorUpdateRequest: Encodable, Sendable {
    let name: String?
    let archived: Bool?
}

/// Der Zeitraum der Effekte, gemerkt - wer 365 Tage sehen will, will das beim
/// naechsten Mal auch.
enum LogbookPeriod {

    static let key = "logbook.period"

    static func load(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: key)
        return LogbookAPI.periods.contains(stored) ? stored : LogbookAPI.defaultPeriod
    }

    static func save(_ days: Int, in defaults: UserDefaults = .standard) {
        defaults.set(days, forKey: key)
    }
}
