import Foundation

// Farbe und Reihenfolge nach Typ (Felix, 2026-10-05): die moderne Liste soll so
// leicht zu verfolgen sein wie die klassische - dieselbe Reihenfolge nach Typ,
// und jedes Co-Habit traegt die Farbe seines Typs statt einer eigenen.
// Welche Farbe ein Typ hat, waehlt seit dem Abend desselben Tages jede Person
// selbst (Vertrag §5.2b): Torben fand alles braun - fast alles sind Streaks,
// und Pfirsich ist im Dunkeln braun.
// Steht hier, damit App und Kachel dieselbe Zuordnung haben.

/// Ein Platz der Typfarben: die vier Typen und „automatisch" - jedes Co-Habit,
/// das von selbst zaehlt, egal welchen Typs.
enum TypeColorSlot: String, CaseIterable, Identifiable, Sendable {
    case streak = "STREAK"
    case abstinence = "ABSTINENCE"
    case goal = "GOAL"
    case challenge = "CHALLENGE"
    case automatic = "AUTOMATIC"

    init(_ type: CohabitType) {
        switch type {
        case .streak: self = .streak
        case .abstinence: self = .abstinence
        case .goal: self = .goal
        case .challenge: self = .challenge
        }
    }

    /// Automatisch geht vor dem Typ: Track food ist ein Streak, sieht aber aus
    /// wie Schritte und Fokus-Zeit.
    init(_ type: CohabitType, automatic: Bool) {
        self = automatic ? .automatic : Self(type)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streak: "Streak"
        case .abstinence: "Abstinenz"
        case .goal: "Ziel"
        case .challenge: "Challenge"
        case .automatic: "Automatisch"
        }
    }

    /// Die Vorgabe - dieselbe wie bei einem Dienst, der die Wahl noch nicht kennt.
    var defaultColor: PaletteKey {
        switch self {
        case .streak: .peach
        case .abstinence: .mint
        case .goal: .periwinkle
        case .challenge: .butter
        case .automatic: .aqua
        }
    }
}

/// Welche Farbe jeder Typ bei dieser Person hat (`MeView.typeColors`,
/// `WidgetData.typeColors`). Was fehlt oder unbekannt ist, hat die Vorgabe -
/// ein Dienst mit einer elften Farbe soll nicht alles in Periwinkle tauchen,
/// wie es `PaletteKey.fallback` taete.
struct TypeColors: Codable, Hashable, Sendable {

    /// Nur, was von der Vorgabe abweicht - so sind zwei gleich aussehende
    /// Zuordnungen auch gleich (`==`), und die App zeichnet nicht umsonst neu.
    private var chosen: [TypeColorSlot: PaletteKey]

    static let defaults = TypeColors()

    init(_ chosen: [TypeColorSlot: PaletteKey] = [:]) {
        self.chosen = chosen.filter { $0.value != $0.key.defaultColor }
    }

    subscript(slot: TypeColorSlot) -> PaletteKey {
        chosen[slot] ?? slot.defaultColor
    }

    func setting(_ color: PaletteKey, for slot: TypeColorSlot) -> TypeColors {
        var copy = chosen
        copy[slot] = color
        return TypeColors(copy)
    }

    func color(for ref: CohabitRef) -> PaletteKey { self[ref.typeColorSlot] }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Liest `{"STREAK":"sky",…}` tolerant: unbekannte Plaetze, unbekannte
    /// Farben, `null` und sogar ein Feld, das gar kein Objekt ist, fallen auf
    /// die Vorgaben - an diesem Feld soll nie ganz `/me` oder `/widget` scheitern.
    init(from decoder: Decoder) throws {
        var chosen: [TypeColorSlot: PaletteKey] = [:]
        if let container = try? decoder.container(keyedBy: Key.self) {
            for slot in TypeColorSlot.allCases {
                if let raw = try? container.decodeIfPresent(String.self, forKey: Key(stringValue: slot.rawValue)),
                   let color = PaletteKey(rawValue: raw) {
                    chosen[slot] = color
                }
            }
        }
        self.init(chosen)
    }

    /// Immer alle fuenf, wie der Dienst sie schickt.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for slot in TypeColorSlot.allCases {
            try container.encode(self[slot].rawValue, forKey: Key(stringValue: slot.rawValue))
        }
    }
}

extension CohabitRef {
    /// Zaehlt von selbst - aus Healthy, Health, dem Wald oder der Evaluation.
    var isAutomatic: Bool { autoSource != nil }

    var typeColorSlot: TypeColorSlot { TypeColorSlot(type, automatic: isAutomatic) }

    /// Die Farbe in der Zuordnung einer Person. Die gespeicherte Farbe
    /// (`storedColor`) zeigt kein Client mehr. In der App heisst das
    /// `typeColor` (mit der Zuordnung der Sitzung); die Kachel nimmt die von
    /// `/widget`.
    func typeColor(in colors: TypeColors) -> PaletteKey { colors[typeColorSlot] }

    /// Die Gruppe in „Heute": wie in der klassischen Liste erst, was man abhakt
    /// (Streaks, dann Ziele und Challenges), dann Abstinenz, zuletzt die
    /// automatischen.
    var todayGroup: TodayGroup {
        if isAutomatic { return .automatic }
        switch type {
        case .streak: return .streak
        case .goal, .challenge: return .goalsAndChallenges
        case .abstinence: return .abstinence
        }
    }
}

extension CohabitConfig {
    /// Die Farbe, die ein neues Co-Habit aus der App mitbekommt - die eigene
    /// seines Typs (Vertrag §5.2b). Gezeigt wird die gespeicherte nirgends
    /// mehr, aeltere Fassungen von Web und Android lesen sie aber noch.
    func typeColor(in colors: TypeColors) -> PaletteKey {
        colors[TypeColorSlot(type, automatic: auto != nil)]
    }
}

enum TodayGroup: Int, Comparable, Sendable {
    case streak, goalsAndChallenges, abstinence, automatic

    static func < (lhs: TodayGroup, rhs: TodayGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Array where Element == CohabitSummary {
    /// Nach Typ-Gruppe, darin nach Anlegedatum (aeltestes zuerst), ohne Datum
    /// (aelterer Dienst) nach Name. Unabhaengig vom Status: was man abhakt,
    /// bleibt, wo es war.
    var typeOrder: [CohabitSummary] {
        enumerated().sorted { a, b in
            let left = a.element.ref, right = b.element.ref
            if left.todayGroup != right.todayGroup { return left.todayGroup < right.todayGroup }
            switch (left.createdAt, right.createdAt) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let byName = left.name.localizedStandardCompare(right.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.offset < b.offset
        }
        .map(\.element)
    }
}
