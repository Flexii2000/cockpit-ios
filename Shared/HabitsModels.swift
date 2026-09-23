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
        /// Fokus-Zeit je Tag - der Wald der Fokus-App entscheidet.
        case focus = "FOCUS"

        /// Ob die Quelle woanders liegt und hier nichts abzuhaken ist.
        var isAutomatic: Bool { self == .food || self == .steps || self == .focus }

        var label: String {
            switch self {
            case .build: "Aufbauen"
            case .quit:  "Lassen"
            case .food:  "Track food"
            case .steps: "Schritte / Woche"
            case .focus: "Fokus-Zeit"
            }
        }
    }

    enum Unit: String, Decodable, Sendable {
        case days = "DAYS"
        case weeks = "WEEKS"
        case months = "MONTHS"
    }

    /// Der Rhythmus eines Habits zum Aufbauen: jeden Tag, oder so-und-so-oft
    /// je Woche oder Monat („Zeitungsartikel lesen: 1x die Woche",
    /// „politisch aktiv sein: 2x im Monat").
    enum Period: String, Decodable, Sendable, CaseIterable {
        case day = "DAY"
        case week = "WEEK"
        case month = "MONTH"

        var label: String {
            switch self {
            case .day:   "Täglich"
            case .week:  "Pro Woche"
            case .month: "Pro Monat"
            }
        }

        /// Hoechstens so oft je Zeitraum.
        var maxTimes: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 31
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind
    let unit: Unit
    let weeklyStepGoal: Int?
    /// Nur bei Fokus-Zeit: das Tagesziel in Minuten. Optional, damit ein
    /// aelterer Dienst die Liste nicht kippt.
    let focusMinutesGoal: Int?
    /// Bei „Aufbauen" der Rhythmus; fehlt er (aelterer Dienst), ist es taeglich.
    let period: Period?
    let timesPerPeriod: Int?
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

    /// „12 Tage", „3 Wochen", „2 Monate".
    var streakText: String {
        switch unit {
        case .days:   streak == 1 ? "1 Tag" : "\(streak) Tage"
        case .weeks:  streak == 1 ? "1 Woche" : "\(streak) Wochen"
        case .months: streak == 1 ? "1 Monat" : "\(streak) Monate"
        }
    }

    /// Der Rhythmus, mit Vorgabe taeglich.
    var rhythm: Period { period ?? .day }

    /// Ob das ein Habit zum Aufbauen mit Wochen- oder Monatsrhythmus ist -
    /// dann zaehlt `progress` die Haken im laufenden Zeitraum.
    var isPeriodic: Bool { kind == .build && rhythm != .day }

    /// „heute noch offen", „diese Woche noch offen", „diesen Monat noch offen".
    var openText: String {
        switch unit {
        case .days:   "heute noch offen"
        case .weeks:  "diese Woche noch offen"
        case .months: "diesen Monat noch offen"
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

    /// „2:15/4:00 h" - Fokus-Minuten des Tages gegen das Ziel.
    var focusText: String {
        "\(HabitProgress.hours(value))/\(HabitProgress.hours(goal)) h"
    }

    static func hours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Was die App beim Anlegen schickt.
struct HabitDraft: Encodable, Sendable {
    let name: String
    let kind: String
    let weeklyStepGoal: Int?
    let focusMinutesGoal: Int?
    var period: String? = nil
    var timesPerPeriod: Int? = nil
}

/// Eine durchgestandene Fokus-Session, wie der Habits-Dienst sie liefert
/// (`/habits/api/focus/sessions`): ein Baum im Wald.
///
/// Anfang und Ende sind Zeitpunkte (`Instant`, ISO-8601 mit `Z`), nicht Tage -
/// `day` ist der Tag, dem der Dienst die Session zurechnet: der des Beginns,
/// in Felix' Zeitzone. Die App rechnet das nicht nach.
struct FocusSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let minutes: Int
    let day: CalendarDate
}

/// Was die App meldet, wenn eine Session durch ist. Die Id vergibt die App,
/// damit ein Nachsenden aus dem Postausgang keinen zweiten Baum pflanzt.
struct FocusSessionDraft: Encodable, Sendable {
    let id: String
    let start: Date
    let end: Date
}
