import Foundation

/// Ein Co-Habit in der Form der alten Habits-API (`GET /classic/habits`, siehe
/// docs/BACKENDS.md) - fuer die klassische Liste.
///
/// Die ersten sechzehn Felder heissen und bedeuten, was der Habits-Tab der
/// Fokus-App bis 2026-09-30 gelesen hat (`HabitStatus`); dazu kommen vier aus
/// coHabit. Wie damals rechnet der Dienst alles: Straehne, „heute erledigt"
/// und „gefaehrdet" kommen fertig an, hier wird nichts nachgezaehlt.
struct ClassicHabit: Identifiable, Sendable, Equatable {

    enum Kind: String, LenientEnum {
        /// Etwas, das man tun will - selbst abhaken. In coHabit ein Streak.
        case build = "BUILD"
        /// Etwas, das man lassen will - zaehlt von selbst, ein Rueckfall setzt
        /// zurueck. In coHabit eine Abstinenz.
        case quit = "QUIT"
        /// „Track food" - der Kalorienzaehler entscheidet.
        case food = "FOOD"
        /// Schritte je Woche - der Weight Tracker entscheidet.
        case steps = "STEPS"
        /// Fokus-Zeit je Tag - der Wald der Fokus-App entscheidet.
        case focus = "FOCUS"
        /// Eine Art, die diese App noch nicht kennt: Name, Flamme und Punkte
        /// stehen da, aber nichts zum Antippen - wie bei den automatischen.
        case unknown = "UNKNOWN"
        static let fallback = Kind.unknown

        /// Was sich anlegen laesst - dieselben fuenf wie frueher.
        static let creatable: [Kind] = [.build, .quit, .food, .steps, .focus]

        /// Ob die Quelle woanders liegt und hier nichts abzuhaken ist.
        var isAutomatic: Bool { self != .build && self != .quit }

        var label: String {
            switch self {
            case .build:   "Aufbauen"
            case .quit:    "Lassen"
            case .food:    "Track food"
            case .steps:   "Schritte / Woche"
            case .focus:   "Fokus-Zeit"
            case .unknown: "Unbekannt"
            }
        }
    }

    enum Unit: String, LenientEnum {
        case days = "DAYS"
        case weeks = "WEEKS"
        case months = "MONTHS"
        /// „alle n Tage" - den Rhythmus gibt es erst in coHabit. Auch die
        /// Rueckfallebene fuer Unbekanntes: „3 Mal" stimmt immer.
        case windows = "WINDOWS"
        static let fallback = Unit.windows
    }

    /// Der Rhythmus eines Habits zum Aufbauen: jeden Tag, oder so-und-so-oft
    /// je Woche oder Monat. Was das alte Formular nicht kennt (Wochentage,
    /// „alle n Tage"), kommt als `null` - und ein unbekannter Wert ebenso.
    enum Period: String, Codable, Sendable, CaseIterable {
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
    /// Nur bei Fokus-Zeit: das Tagesziel in Minuten.
    let focusMinutesGoal: Int?
    /// Bei „Aufbauen" der Rhythmus; `nil` heisst: einer, den das alte
    /// Formular nicht zeigen kann.
    let period: Period?
    let timesPerPeriod: Int?
    let streak: Int
    let doneToday: Bool
    /// Heute noch nicht erledigt, aber die Straehne lebt - bis Mitternacht.
    let atRisk: Bool
    let progress: ClassicProgress?
    /// Die letzten sieben Zeitraeume, aelteste zuerst.
    let recent: [Bool]
    /// Gesetzt, wenn die Quelle nicht erreichbar war. Dann taugen Straehne
    /// und Punkte nichts, und statt der Flamme steht dieser Satz.
    let unavailable: String?
    /// Die Tage der letzten 31 mit eigenem Eintrag - Haken bzw. Rueckfall.
    let markedDays: [CalendarDate]
    /// Ab wann Eintraege zaehlen: Start bzw. der eigene Beitritt.
    let createdAt: CalendarDate?
    /// Abhaken nur mit Beweisfoto - aus der Liste heraus geht das nicht direkt.
    let photoRequired: Bool
    /// Mehr als ein Mitglied: Loeschen heisst dann Verlassen.
    let shared: Bool
    /// Ob die Person die Einstellungen aendern darf.
    let admin: Bool
    /// Der frueheste Tag, den der Dienst noch annimmt.
    let backfillFrom: CalendarDate?

    func isMarked(_ day: CalendarDate) -> Bool {
        markedDays.contains(day)
    }

    /// „12 Tage", „3 Wochen", „2 Monate", „4 Mal".
    var streakText: String {
        switch unit {
        case .days:    streak == 1 ? "1 Tag" : "\(streak) Tage"
        case .weeks:   streak == 1 ? "1 Woche" : "\(streak) Wochen"
        case .months:  streak == 1 ? "1 Monat" : "\(streak) Monate"
        case .windows: "\(streak) Mal"
        }
    }

    /// Der Rhythmus, mit Vorgabe taeglich.
    var rhythm: Period { period ?? .day }

    /// Ob das ein Habit zum Aufbauen mit Wochen- oder Monatsrhythmus ist -
    /// dann zaehlt `progress` die Haken im laufenden Zeitraum.
    var isPeriodic: Bool { kind == .build && rhythm != .day }

    /// Ob das alte Formular den Rhythmus zeigen kann. Wochentage oder „alle n
    /// Tage" kann es nicht - dann blendet es ihn aus und laesst ihn stehen.
    var hasClassicRhythm: Bool { kind != .build || period != nil }

    /// „heute noch offen", „diese Woche noch offen", „diesen Monat noch offen".
    var openText: String {
        switch unit {
        case .days:    "heute noch offen"
        case .weeks:   "diese Woche noch offen"
        case .months:  "diesen Monat noch offen"
        case .windows: "noch offen"
        }
    }

    /// Foto-Pflicht zaehlt nur beim Abhaken - einen Rueckfall traegt man ohne
    /// Beweisfoto ein.
    var needsPhoto: Bool { photoRequired && kind == .build }

    /// Langdruck: fruehere Tage nachtragen. Nur, was man selbst abhakt, und
    /// nicht mit Foto-Pflicht - zu jedem Tag gehoerte dann ein Foto.
    var canBackfill: Bool { !kind.isAutomatic && !needsPhoto }

    /// Heute in der Zone des Co-Habits wie beim Abhaken in coHabit
    /// (`CheckInTarget.today`), nicht in der des Geraets.
    var today: CalendarDate {
        .today(in: CohabitGroup.zone(for: id) ?? CheckInTarget.defaultZone)
    }

    /// Die Tage im Nachtragen-Blatt: die letzten 14, neueste zuerst - aber
    /// keiner vor dem Start bzw. Beitritt und keiner vor dem fruehesten Tag,
    /// den der Dienst noch annimmt.
    func backfillDays(today: CalendarDate) -> [CalendarDate] {
        (0..<14).map { today.adding(days: -$0) }
            .filter { day in createdAt.map { day >= $0 } ?? true }
            .filter { day in backfillFrom.map { day >= $0 } ?? true }
    }
}

extension ClassicHabit: Decodable {
    /// Nachsichtig: ein unbekannter Wert (neue Art, neuer Rhythmus) oder ein
    /// fehlendes Nebenfeld soll nicht die ganze Liste leer lassen. Streng sind
    /// nur die Felder, ohne die eine Zeile nichts zeigen koennte.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        unit = try c.decode(Unit.self, forKey: .unit)
        weeklyStepGoal = try? c.decodeIfPresent(Int.self, forKey: .weeklyStepGoal)
        focusMinutesGoal = try? c.decodeIfPresent(Int.self, forKey: .focusMinutesGoal)
        period = try? c.decodeIfPresent(Period.self, forKey: .period)
        timesPerPeriod = try? c.decodeIfPresent(Int.self, forKey: .timesPerPeriod)
        streak = try c.decode(Int.self, forKey: .streak)
        doneToday = try c.decode(Bool.self, forKey: .doneToday)
        atRisk = try c.decode(Bool.self, forKey: .atRisk)
        progress = try? c.decodeIfPresent(ClassicProgress.self, forKey: .progress)
        recent = (try? c.decodeIfPresent([Bool].self, forKey: .recent)) ?? []
        unavailable = try? c.decodeIfPresent(String.self, forKey: .unavailable)
        markedDays = (try? c.decodeIfPresent([CalendarDate].self, forKey: .markedDays)) ?? []
        createdAt = try? c.decodeIfPresent(CalendarDate.self, forKey: .createdAt)
        photoRequired = (try? c.decodeIfPresent(Bool.self, forKey: .photoRequired)) ?? false
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? false
        admin = (try? c.decodeIfPresent(Bool.self, forKey: .admin)) ?? false
        backfillFrom = try? c.decodeIfPresent(CalendarDate.self, forKey: .backfillFrom)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, unit, weeklyStepGoal, focusMinutesGoal, period, timesPerPeriod,
             streak, doneToday, atRisk, progress, recent, unavailable, markedDays, createdAt,
             photoRequired, shared, admin, backfillFrom
    }
}

extension Array where Element == ClassicHabit {
    /// Erst, was man selbst abhakt (Aufbauen, Lassen), dann, was von selbst
    /// zaehlt (Track food, Schritte, Fokus-Zeit) - der Dienst liefert in
    /// Anlegereihenfolge, die bleibt innerhalb der Gruppen erhalten. Felix'
    /// Wunsch vom 2026-09-23, wie frueher.
    var manualFirst: [ClassicHabit] {
        filter { !$0.kind.isAutomatic } + filter { $0.kind.isAutomatic }
    }
}

/// Wie weit der laufende Zeitraum ist - Schritte gegen das Wochenziel, kcal
/// gegen die 80 % des Tagesziels, Fokus-Minuten gegen das Tagesziel, Haken
/// gegen die Haeufigkeit.
struct ClassicProgress: Decodable, Sendable, Equatable {
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
        "\(ClassicProgress.hours(value))/\(ClassicProgress.hours(goal)) h"
    }

    static func hours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Was das alte Formular beim Anlegen (`POST /classic/habits`) und Bearbeiten
/// (`PUT /classic/habits/{id}`) schickt.
///
/// Alle Schluessel stehen da, leere als `null` - wie ueberall in coHabit.
/// `period: null` heisst beim Bearbeiten „Rhythmus nicht anfassen".
struct ClassicHabitDraft: Encodable, Sendable, Equatable {
    let name: String
    let kind: ClassicHabit.Kind
    var weeklyStepGoal: Int?
    var focusMinutesGoal: Int?
    var period: ClassicHabit.Period?
    var timesPerPeriod: Int?

    init(name: String, kind: ClassicHabit.Kind, weeklyStepGoal: Int? = nil, focusMinutesGoal: Int? = nil,
         period: ClassicHabit.Period? = nil, timesPerPeriod: Int? = nil) {
        self.name = name
        self.kind = kind
        self.weeklyStepGoal = weeklyStepGoal
        self.focusMinutesGoal = focusMinutesGoal
        self.period = period
        self.timesPerPeriod = timesPerPeriod
    }

    /// Was das Formular aus seinen Feldern macht: Ziele nur bei ihrer Art,
    /// Rhythmus nur beim Aufbauen und nur, wenn das Formular ihn zeigt
    /// (`period` sonst `nil`), die Haeufigkeit nur bei Woche und Monat.
    init(form name: String, kind: ClassicHabit.Kind, stepGoal: Int?, focusMinutes: Int?,
         period: ClassicHabit.Period?, timesPerPeriod: Int) {
        let rhythm = kind == .build ? period : nil
        self.init(name: name, kind: kind,
                  weeklyStepGoal: kind == .steps ? stepGoal : nil,
                  focusMinutesGoal: kind == .focus ? focusMinutes : nil,
                  period: rhythm,
                  timesPerPeriod: rhythm == .week || rhythm == .month ? timesPerPeriod : nil)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(weeklyStepGoal, forKey: .weeklyStepGoal)
        try c.encode(focusMinutesGoal, forKey: .focusMinutesGoal)
        try c.encode(period, forKey: .period)
        try c.encode(timesPerPeriod, forKey: .timesPerPeriod)
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, weeklyStepGoal, focusMinutesGoal, period, timesPerPeriod
    }
}

/// Der Schalter „Klassische Liste" im Profil: an, zeigt „Heute" die alte
/// Liste statt Dashboard und Liste. Gilt je Geraet wie die Wahl
/// Dashboard/Liste (`@AppStorage`).
enum ClassicList {
    static let storageKey = "today.classic"

    #if DEBUG
    /// `COCKPIT_CLASSIC=1` schaltet die klassische Liste beim Start ein, `0`
    /// aus - fuer Simulator-Bilder ohne Tippen und UI-Tests, die mit einem
    /// bekannten Stand beginnen muessen (der Schalter ueberlebt jeden Lauf).
    static func applyEnvironment() {
        switch ProcessInfo.processInfo.environment["COCKPIT_CLASSIC"] {
        case "1": UserDefaults.standard.set(true, forKey: storageKey)
        case "0": UserDefaults.standard.set(false, forKey: storageKey)
        default: break
        }
    }
    #endif
}
