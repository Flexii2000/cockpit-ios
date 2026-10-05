import Foundation

// Farbe und Reihenfolge nach Typ (Felix, 2026-10-05): die moderne Liste soll so
// leicht zu verfolgen sein wie die klassische - dieselbe Reihenfolge nach Typ,
// und jedes Co-Habit traegt die Farbe seines Typs statt einer eigenen.
// Steht hier, damit App und Kachel dieselbe Zuordnung haben.

extension CohabitType {
    /// Die Farbe eines Typs - dieselbe wie auf den Typkarten im Anlegen-Schritt 1;
    /// automatische (Track food, Schritte, Fokus-Zeit …) sind immer Aqua.
    func color(automatic: Bool) -> PaletteKey {
        automatic ? .aqua : palette
    }
}

extension CohabitRef {
    /// Zaehlt von selbst - aus Healthy, Health, dem Wald oder der Evaluation.
    var isAutomatic: Bool { autoSource != nil }

    /// Die Farbe in der App, ueberall: Streak Pfirsich, Abstinenz Minze, Ziel
    /// Flieder, Challenge Butter, automatisch Aqua. Die gespeicherte Farbe
    /// (`storedColor`) zeigen nur noch Web und Android.
    var typeColor: PaletteKey { type.color(automatic: isAutomatic) }

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
    /// Die Farbe, die ein neues Co-Habit aus der App mitbekommt - die seines
    /// Typs, damit Web und Android dieselbe zeigen.
    var typeColor: PaletteKey { type.color(automatic: auto != nil) }
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
