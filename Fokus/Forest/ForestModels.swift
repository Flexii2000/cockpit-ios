import Foundation

/// Eine laufende Session: der Baum, der gerade waechst.
///
/// Liegt in den UserDefaults, nicht nur im Speicher - die App darf
/// zwischendurch beendet werden (oder Felix beendet sie, um an die Sperre
/// vorbeizukommen: das hilft nicht, die Sperre haelt der Bildschirmzeit-Dienst).
/// Abbrechen gibt es nicht: die Session endet, wenn `end` erreicht ist.
struct ActiveSession: Codable, Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }

    func isOver(at now: Date = Date()) -> Bool { now >= end }

    /// 0 beim Pflanzen, 1 am Ende - so weit ist der Baum gewachsen.
    func growth(at now: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}

/// Wie gross ein Baum im Wald gezeichnet wird: nach Dauer, nicht nach Wert -
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

    var pointSize: CGFloat {
        switch self {
        case .sapling: 22
        case .young:   30
        case .grown:   38
        case .old:     46
        }
    }
}

/// Die Dauern, die sich waehlen lassen. Unter 30 Minuten ist kein Fokus,
/// das war Felix' Vorgabe; nach oben ist bei vier Stunden Schluss - laenger
/// sperrt niemand sein Handy am Stueck.
enum SessionLength {
    static let choices = [30, 45, 60, 75, 90, 120, 150, 180, 240]
    static let minimum = 30
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
