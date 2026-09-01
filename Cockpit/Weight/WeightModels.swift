import Foundation

/// Ein Tag in der Gewichtskurve.
///
/// `measured` ist der gewogene Wert (fehlt an Tagen ohne Messung), die
/// `avg…`-Werte sind gleitende Mittel. Die `…Complete`-Flags sagen, ob das
/// Fenster voll besetzt war - am aktuellen Rand ist es das nie, und dort
/// wird die Linie gepunktet gezeichnet statt durchgezogen.
struct WeightPoint: Decodable, Identifiable, Sendable {
    let date: CalendarDate
    let measured: Double?
    let avg7: Double?
    let avg14: Double?
    let avg30: Double?
    let avg7Complete: Bool
    let avg14Complete: Bool
    let avg30Complete: Bool
    let target: Double?

    var id: CalendarDate { date }
}

struct WeightSummary: Decodable, Sendable {
    let date: CalendarDate?
    let current: Double?
    let avg7: Double?
    let avg14: Double?
    let avg30: Double?
    /// Der Tageswert der Zielkurve - nicht das Zielgewicht, das ist `goalWeight`.
    let target: Double?
    let targetDate: CalendarDate?
    let goalWeight: Double?
    let startWeight: Double?
    let recordingStart: CalendarDate?
    let corridorLower: Double?
    let corridorUpper: Double?
    /// Der Tag, an dem die Korridor-Obergrenze erstmals unterschritten wurde.
    /// Vorher gibt es keinen Korridor, an dem man sich messen wuerde.
    let corridorReachedOn: CalendarDate?

    /// Liegt der aktuelle Wert im Zielkorridor? Erst ab `corridorReachedOn`.
    var isInCorridor: Bool {
        guard corridorReachedOn != nil,
              let current, let lower = corridorLower, let upper = corridorUpper
        else { return false }
        return current >= lower && current <= upper
    }

    /// Der Korridor, sobald er gilt - sonst nichts zu zeichnen.
    var activeCorridor: (lower: Double, upper: Double)? {
        guard corridorReachedOn != nil,
              let lower = corridorLower, let upper = corridorUpper
        else { return nil }
        return (lower, upper)
    }
}

struct Vacation: Decodable, Identifiable, Sendable {
    let start: CalendarDate
    let end: CalendarDate
    let label: String?

    var id: String { "\(start.iso)/\(end.iso)" }
}

struct DashboardConfig: Codable, Sendable {
    let widgets: [String]
}

struct NewWeightRequest: Encodable, Sendable {
    let date: CalendarDate
    let weightKg: Double
}

struct UpdateTargetRequest: Encodable, Sendable {
    let targetWeightKg: Double
}

/// Zeitraum der Kurve. Die Weboberflaeche stapelt vier Diagramme untereinander;
/// auf dem Handy ist ein Diagramm mit Umschalter die bessere Form - vier
/// Diagramme hintereinander bedeuten dort nur viel Scrollen.
enum WeightRange: String, CaseIterable, Identifiable, Sendable {
    case month, last90, year, allTime

    var id: String { rawValue }

    var path: String {
        switch self {
        case .month:   "/api/weight/month"
        case .last90:  "/api/weight/last90"
        case .year:    "/api/weight/year"
        case .allTime: "/api/weight/all-time"
        }
    }

    var title: String {
        switch self {
        case .month:   "30 Tage"
        case .last90:  "90 Tage"
        case .year:    "1 Jahr"
        case .allTime: "Alles"
        }
    }

    /// Ein 30-Tage-Mittel ueber ein 30-Tage-Fenster ergibt keinen Sinn, ein
    /// 14er darin kaum mehr - dieselbe Einschraenkung wie in der Weboberflaeche.
    var availableSeries: [WeightSeries] {
        switch self {
        case .month: [.measured, .avg7, .target, .kcal]
        default:     [.measured, .avg7, .avg14, .avg30, .target, .kcal]
        }
    }
}

enum WeightSeries: String, CaseIterable, Identifiable, Sendable {
    case measured, avg7, avg14, avg30, target
    /// Die Tageskalorien aus dem Kalorienzaehler. Sie liegen auf einer
    /// eigenen Skala und werden in den Gewichtsbereich hineingerechnet -
    /// dieselbe Zusammenschau wie in der Weboberflaeche.
    case kcal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measured: "Messwert"
        case .avg7:     "7-Tage-Mittel"
        case .avg14:    "14-Tage-Mittel"
        case .avg30:    "30-Tage-Mittel"
        case .target:   "Zielkurve"
        case .kcal:     "kcal"
        }
    }

    /// Die langen Mittel sind in der Weboberflaeche seit laengerem
    /// ausgeblendet (`SHOW_LONG_AVERAGES = false`); hier gar nicht erst
    /// anbieten, statt einen Umschalter zu zeigen, den niemand benutzt.
    static let offered: [WeightSeries] = [.measured, .avg7, .target, .kcal]

    static let defaultVisible: Set<WeightSeries> = [.avg7, .target, .kcal]
}
