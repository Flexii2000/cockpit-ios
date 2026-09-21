import Foundation

/// Welche Art Baum eine Session wird: nach Dauer, nicht nach Wert -
/// laenger fokussiert, groesserer Baum.
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

/// Die Dauern, die sich waehlen lassen. Unter 30 Minuten ist kein Fokus,
/// das war Felix' Vorgabe; nach oben ist bei vier Stunden Schluss - laenger
/// sperrt niemand sein Handy am Stueck.
enum SessionLength {
    static let choices = [30, 45, 60, 75, 90, 120, 150, 180, 240]
    static let minimum = 30
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
