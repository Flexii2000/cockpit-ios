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
    /// Ob der Schild schon liegt. Er kommt erst, wenn der Kurzbefehl durch
    /// ist: die Kurzbefehle-App ist selbst eine App und laege sonst mit
    /// darunter - „Fokus an" koennte nie laufen.
    var shielded = false
    /// Der Testbaum: gleicher Ablauf, aber am Ende kein Baum und keine
    /// Minuten - er zaehlt nirgends.
    let test: Bool

    init(id: String, start: Date, end: Date, shielded: Bool = false, test: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.shielded = shielded
        self.test = test
    }

    /// `shielded` und `test` duerfen fehlen: eine Session aus einem Stand,
    /// der die Felder noch nicht kannte, gilt als geschuetzt und echt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        shielded = try container.decodeIfPresent(Bool.self, forKey: .shielded) ?? true
        test = try container.decodeIfPresent(Bool.self, forKey: .test) ?? false
    }

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
