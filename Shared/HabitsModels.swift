import Foundation

/// Was `/habits/api/habits` je Habit liefert. Siehe docs/BACKENDS.md.
///
/// Der Server rechnet, die App zeigt: Straehne, „heute erledigt" und
/// „gefaehrdet" kommen fertig an. Hier wird nichts nachgezaehlt - die
/// Regeln (heute darf offen sein, Woche ab Montag) stehen an genau einer
/// Stelle, und die ist dort.
struct HabitStatus: Decodable, Identifiable, Sendable, Equatable {

    enum Kind: String, Decodable, Sendable, CaseIterable {
        /// Etwas, das man tun will - selbst abhaken.
        case build = "BUILD"
        /// Etwas, das man lassen will - zaehlt von selbst, ein Rueckfall setzt zurueck.
        case quit = "QUIT"
        /// „Track food" - der Kalorienzaehler entscheidet.
        case food = "FOOD"
        /// Schritte je Woche - der Weight Tracker entscheidet.
        case steps = "STEPS"

        /// Ob die Quelle woanders liegt und hier nichts abzuhaken ist.
        var isAutomatic: Bool { self == .food || self == .steps }

        var label: String {
            switch self {
            case .build: "Aufbauen"
            case .quit:  "Lassen"
            case .food:  "Track food"
            case .steps: "Schritte / Woche"
            }
        }
    }

    enum Unit: String, Decodable, Sendable {
        case days = "DAYS"
        case weeks = "WEEKS"
    }

    let id: String
    let name: String
    let kind: Kind
    let unit: Unit
    let weeklyStepGoal: Int?
    let streak: Int
    let doneToday: Bool
    /// Heute noch nicht erledigt, aber die Straehne lebt - bis Mitternacht.
    let atRisk: Bool
    let progress: HabitProgress?
    /// Die letzten sieben Zeitraeume, aelteste zuerst.
    let recent: [Bool]
    /// Gesetzt, wenn die Quelle nicht erreichbar war. Dann taugen Straehne
    /// und Punkte nichts, und statt der Flamme steht dieser Satz.
    let unavailable: String?

    /// „12 Tage", „3 Wochen".
    var streakText: String {
        switch unit {
        case .days:  streak == 1 ? "1 Tag" : "\(streak) Tage"
        case .weeks: streak == 1 ? "1 Woche" : "\(streak) Wochen"
        }
    }
}

/// Wie weit der laufende Zeitraum ist - Schritte gegen das Wochenziel,
/// kcal gegen die 80 % des Tagesziels.
struct HabitProgress: Decodable, Sendable, Equatable {
    let value: Int
    let goal: Int

    var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(value) / Double(goal), 1)
    }

    /// „55/70k" - so hat Felix es aufgeschrieben. Auch ueber dem Ziel
    /// („98/70k"): dass es mehr war, ist genau das, was man sehen will.
    /// Nur bei runden Tausendern; ein Ziel wie 75.500 bekommt volle Zahlen.
    var stepsText: String {
        guard goal % 1000 == 0 else { return "\(value.formatted())/\(goal.formatted())" }
        let thousands = Int((Double(value) / 1000).rounded())
        return "\(thousands)/\(goal / 1000)k"
    }

    /// „1.470/1.840 kcal".
    var kcalText: String {
        "\(value.formatted())/\(goal.formatted()) kcal"
    }
}

/// Was die App beim Anlegen schickt.
struct HabitDraft: Encodable, Sendable {
    let name: String
    let kind: String
    let weeklyStepGoal: Int?
}
