import Foundation

/// Wie gross ein Baum wird: nach Dauer, nicht nach Wert - laenger
/// fokussiert, groesserer Baum. Die Art (Tanne, Birke, Bluetenbaum …) kommt
/// aus dem Zufall der Session-Id, damit der Wald bunt wird.
enum TreeSize: Comparable {
    case sapling, young, grown, old

    init(minutes: Int) {
        switch minutes {
        case ..<45:   self = .sapling
        case ..<90:   self = .young
        case ..<150:  self = .grown
        default:      self = .old
        }
    }

    /// Der Massstab gegenueber einem ausgewachsenen Baum.
    var scale: Float {
        switch self {
        case .sapling: 0.55
        case .young:   0.8
        case .grown:   1.0
        case .old:     1.25
        }
    }
}

/// Welcher Ausschnitt des Waldes zu sehen ist.
enum ForestRange: String, CaseIterable, Identifiable {
    case today, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Heute"
        case .week:  "Woche"
        case .month: "Monat"
        case .year:  "Jahr"
        }
    }

    /// Wie viele Tage zurueck, den heutigen mitgezaehlt.
    var days: Int {
        switch self {
        case .today: 1
        case .week:  7
        case .month: 30
        case .year:  365
        }
    }

    func contains(_ day: CalendarDate, today: CalendarDate = .today()) -> Bool {
        guard day <= today else { return false }
        let calendar = Calendar(identifier: .gregorian)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today.startOfDay())
        else { return true }
        return day >= CalendarDate(date: first)
    }
}

/// Die Dauern im Rad. Ab 30 Minuten, das war Felix' Vorgabe fuer die
/// Vorgaben; wer etwas anderes will - 11, 22, 56, 71 Minuten - tippt es
/// unter „Eigene Dauer" ein, dort gilt nur die Untergrenze von einer Minute.
/// Nach oben ist bei einem Tag Schluss, mehr nimmt der Dienst nicht an.
enum SessionLength {
    static let choices = [30, 45, 60, 75, 90, 120, 150, 180, 240]
    static let minimum = 30
    static let customMinimum = 1
    static let maximum = 24 * 60
    /// Der Testbaum: zwanzig Sekunden, um den Ablauf durchzuspielen - Schild,
    /// Meldung, Kurzbefehle. Steht nicht im Rad, sondern im Menue, und
    /// zaehlt nirgends.
    static let testSeconds: TimeInterval = 20
}

/// Ein Tag im Wald: seine Baeume und ihre Minuten.
struct ForestDay: Identifiable {
    let day: CalendarDate
    let sessions: [FocusSession]

    var id: CalendarDate { day }
    var minutes: Int { sessions.reduce(0) { $0 + $1.minutes } }

    /// Neueste Tage zuerst, innerhalb des Tages der aelteste Baum links -
    /// so, wie er gepflanzt wurde.
    static func group(_ sessions: [FocusSession]) -> [ForestDay] {
        let byDay = Dictionary(grouping: sessions, by: \.day)
        return byDay.keys.sorted(by: >).map { day in
            ForestDay(day: day, sessions: byDay[day]!.sorted { $0.start < $1.start })
        }
    }
}
