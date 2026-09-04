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

/// Welche Kacheln der Gewicht-Tab zeigt, in dieser Reihenfolge.
///
/// Die Liste ist **vollstaendig**: es gibt keine Kacheln mehr, die unabhaengig
/// davon davorstehen. Die Version sagt dem Server genau das - ohne sie
/// ergaenzt er die vier frueher fest verdrahteten, damit ein Client, der die
/// Umstellung nicht kennt, sie nicht loeschen kann.
struct DashboardConfig: Codable, Sendable {
    let widgets: [String]
    var version: Int? = 1
}

struct NewWeightRequest: Encodable, Sendable {
    let date: CalendarDate
    let weightKg: Double
    /// Laesst einen bereits vorhandenen Wert fuer diesen Tag stehen.
    ///
    /// Gesetzt nur beim Abgleich mit Apple Health: es gibt genau einen Wert
    /// pro Tag, und der von Hand eingetragene ist der verlaesslichere. Wer im
    /// Browser oder hier von Hand eintraegt, ueberschreibt weiterhin.
    let keepExisting: Bool?
}

struct UpdateTargetRequest: Encodable, Sendable {
    let targetWeightKg: Double
}

/// Zeitraum der Kurve. Die Weboberflaeche stapelt vier Diagramme untereinander;
/// auf dem Handy ist ein Diagramm mit Umschalter die bessere Form - vier
/// Diagramme hintereinander bedeuten dort nur viel Scrollen.
enum WeightRange: String, CaseIterable, Identifiable, Sendable {
    case month, last90, year, threeYears, allTime

    var id: String { rawValue }

    var path: String {
        switch self {
        case .month:      "/api/weight/month"
        case .last90:     "/api/weight/last90"
        case .year:       "/api/weight/year"
        // Fuer drei Jahre gibt es keinen eigenen Endpunkt; die volle Reihe
        // wird geholt und im Client zugeschnitten. Sie ist klein genug, und
        // ein Endpunkt je Zeitraum waere Backend-Arbeit fuer eine reine
        // Anzeigefrage.
        case .threeYears: "/api/weight/all-time"
        case .allTime:    "/api/weight/all-time"
        }
    }

    /// Wie weit die Ansicht zurueckreicht. `nil` heisst: der Endpunkt
    /// schneidet schon selbst zu.
    var windowDays: Int? {
        switch self {
        case .threeYears: 1095
        default:          nil
        }
    }

    /// Vorgriff wie beim Jahres-Endpunkt: eine Woche, damit die Zielkurve
    /// nicht am rechten Rand abgeschnitten wirkt.
    static let lookAheadDays = 7

    var title: String {
        switch self {
        case .month:      "30 Tage"
        case .last90:     "90 Tage"
        case .year:       "1 Jahr"
        case .threeYears: "3 Jahre"
        case .allTime:    "Alles"
        }
    }

    /// Was die Umschalter unter dem Diagramm anbieten. „Alles" tauscht das
    /// 7-Tage-Mittel gegen das 30-Tage-Mittel: ueber acht Jahre ist das
    /// 7er fast so unruhig wie die Messwerte, das 30er zeigt den Verlauf.
    /// Ein fuenfter Umschalter passte nicht in die Reihe.
    var offeredSeries: [WeightSeries] {
        switch self {
        case .allTime: [.measured, .avg30, .target, .kcal]
        default:       WeightSeries.offered
        }
    }

    /// Womit der Zeitraum aufmacht. „Alles" ohne kcal: acht Jahre Tageswerte
    /// waeren nur Rauschen ueber der Kurve, die man sehen will.
    var defaultVisible: Set<WeightSeries> {
        switch self {
        case .allTime: [.avg30, .target]
        default:       WeightSeries.defaultVisible
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

    /// Das Angebot der kurzen Zeitraeume - dieselbe Aufteilung wie in der
    /// Weboberflaeche (`offeredSeries` in app.js): die langen Mittel dort
    /// nicht anbieten, statt einen Umschalter zu zeigen, den niemand
    /// benutzt. „Alles" hat sein eigenes Angebot, siehe `WeightRange`.
    static let offered: [WeightSeries] = [.measured, .avg7, .target, .kcal]

    static let defaultVisible: Set<WeightSeries> = [.avg7, .target, .kcal]
}

/// Was die App an /api/steps schickt.
struct StepsUpload: Encodable, Sendable {
    let days: [StepDay]
    /// `true` laesst Werte auch sinken - fuer den Fall, dass jemand Messungen
    /// in Health geloescht hat. Sonst gewinnt im Backend das Maximum.
    let replace: Bool?
}

struct StepsGoal: Codable, Sendable {
    let stepsPerDay: Int
}
