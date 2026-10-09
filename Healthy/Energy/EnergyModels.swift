import Foundation

/// Ein Aufzaehlungstyp des Dienstes, der unbekannte Werte vertraegt.
///
/// Ein neuer Status beim Weight Tracker soll nicht die ganze Antwort
/// unlesbar machen - die Karte saehe sonst nach einem Dienst-Update leer aus,
/// bis auch die App eins hat. Unbekanntes wird `unknown` und angezeigt wie
/// „kein Wert".
protocol LenientEnum: RawRepresentable, Decodable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension LenientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

/// Ob der Verbrauch der Uhr am Gewicht abgeglichen werden konnte. Nur `ok`
/// und `clamped` tragen einen eigenen Faktor; sonst gilt 1.
enum CalibrationStatus: String, LenientEnum {
    case ok = "OK"
    /// Der gemessene Faktor lag ausserhalb von 0,7 bis 1,3.
    case clamped = "CLAMPED"
    case tooFewTrackedDays = "TOO_FEW_TRACKED_DAYS"
    case tooFewWeights = "TOO_FEW_WEIGHTS"
    case tooFewWatchDays = "TOO_FEW_WATCH_DAYS"
    case foodUnavailable = "FOOD_UNAVAILABLE"
    case unknown
}

/// Ein Tag der Energiebilanz (`GET /api/energy`), gerechnet im Weight
/// Tracker - die App rechnet hier nichts nach (Vertrag §1.2).
struct EnergyDay: Decodable, Identifiable, Equatable, Sendable {
    let date: CalendarDate
    let activeKcal: Double?
    let basalKcal: Double?
    /// Die Uhr war nur teilweise getragen; statt der Ruheenergie steht der
    /// Median der 28 Tage davor da.
    let basalImputed: Bool
    /// Ruhe- plus Aktivenergie der Uhr - heute mit hochgerechneter Ruhe.
    let watchKcal: Double?
    /// Der Kalibrierfaktor dieses Tages (aus den 28 Tagen davor).
    let factor: Double
    let calibrationStatus: CalibrationStatus
    /// Der kalibrierte Verbrauch: `watchKcal × factor`.
    let expenditureKcal: Double?
    /// Gegessen laut Kalorienzaehler; `nil` ohne Eintrag.
    let intakeKcal: Double?
    /// Wie „Track food" in coHabit: 80 % des Ziels oder drei Mahlzeiten.
    let tracked: Bool
    /// Verbrauch minus gegessen, nur an getrackten Tagen und heute; negativ
    /// ist ein Ueberschuss.
    let deficitKcal: Double?
    /// Heute: Prognose fuer das Tagesende, „falls nichts mehr dazukommt".
    let projected: Bool
    /// Zentriertes 7-Tage-Mittel des Verbrauchs - die Kurve „Verbrauch ⌀".
    let expenditureAvg7: Double?
    /// Zentriertes 7-Tage-Mittel des Defizits ueber die **getrackten**,
    /// abgeschlossenen Tage D−3 … D+3 - die Kurve „Defizit ⌀". `nil`, wenn
    /// keiner dabei ist, und bei einem Dienst von vor dem Feld.
    let deficitAvg7: Double?
    /// Ob das Fenster der beiden Mittel schon ganz vorbei ist; sonst gestrichelt.
    let avg7Complete: Bool

    var id: CalendarDate { date }

    /// Das Mittel in der Form, die die kcal-Kurven schon haben - so laeuft
    /// „Verbrauch ⌀" durch dieselbe Zerlegung an Luecken und am vorlaeufigen
    /// Rand wie „kcal ⌀".
    var expenditureAverage: DayAverage? {
        expenditureAvg7.map { DayAverage(date: date, kcal: $0, days: 7, complete: avg7Complete) }
    }

    /// „Defizit ⌀" ebenso. Negativ ist ein Ueberschuss; `avg7Complete` gilt
    /// fuer beide Mittel (Vertrag §1.2).
    var deficitAverage: DayAverage? {
        deficitAvg7.map { DayAverage(date: date, kcal: $0, days: 7, complete: avg7Complete) }
    }
}

/// Der Abgleich der Uhr am Gewicht fuer einen Tag (Vertrag §1.4).
struct Calibration: Decodable, Equatable, Sendable {
    let status: CalibrationStatus
    /// Was gilt - 1 ohne genug Daten.
    let factor: Double
    let rawFactor: Double?
    let windowFrom: CalendarDate?
    let windowTo: CalendarDate?
    let measuredKcal: Double?
    let measuredSeKcal: Double?
    let watchKcal: Double?
    let intakeKcal: Double?
    let weightSlopeKgPerWeek: Double?
    /// Getrackte Tage im Fenster - die Notiz unter der Kachel „Kalibrierung".
    let trackedDays: Int
    let weightDays: Int
    let watchDays: Int
}

/// `GET /api/energy/summary`: heute und die letzten sieben vollen Tage - fuer
/// die Kacheln im Gewicht-Tab und die Karte im Dashboard.
struct EnergySummary: Decodable, Equatable, Sendable {
    /// `nil`, solange es heute weder Werte der Uhr noch einen Eintrag gibt.
    let today: EnergyDay?
    let deficit7: Double?
    let deficit7Days: Int
    let expenditure7: Double?
    let expenditure7Days: Int
    let calibration: Calibration
    /// Ob der Kalorienzaehler antwortete (`food: OK|UNAVAILABLE`).
    let sources: [String: String]

    /// Ohne Kalorienzaehler kennt der Dienst das Gegessene nicht - ein
    /// Defizit waere dann der ganze Verbrauch.
    var foodAvailable: Bool { sources["food"] != "UNAVAILABLE" }
}

/// Aktive Energie und Ruheenergie eines Tages, wie sie zum Weight Tracker
/// gehen (`POST /api/energy`, Vertrag §1.1). Ein fehlendes Feld heisst
/// „unbekannt" und laesst beim Dienst den gespeicherten Wert stehen.
struct EnergyDayUpload: Codable, Equatable, Sendable {
    let date: CalendarDate
    let activeKcal: Double?
    let basalKcal: Double?
}

/// Was die App an `POST /api/energy` schickt.
struct EnergyUpload: Encodable, Sendable {
    let days: [EnergyDayUpload]
    /// `true` liesse auch heute und gestern sinken - die App schickt das nie;
    /// heute und gestern gewinnt beim Dienst je Feld das Maximum.
    let replace: Bool?
}
