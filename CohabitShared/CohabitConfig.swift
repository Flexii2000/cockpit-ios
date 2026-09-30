import Foundation

/// Die Einstellungen eines Co-Habits (Vertrag §2.2, `CohabitConfig` in §3.4) -
/// in beide Richtungen: der Dienst liefert sie im Detail, die App schickt sie
/// beim Anlegen und Bearbeiten.
///
/// Beim Senden stehen alle Schluessel da, auch die leeren als `null`: ein
/// fehlender Schluessel koennte beim Bearbeiten als „nicht aendern" gelesen
/// werden, `null` heisst eindeutig „keins" (keine Erinnerung, kein Ziel).
struct CohabitConfig: Codable, Hashable, Sendable {

    struct Tracking: Codable, Hashable, Sendable {
        /// `CHECK` oder `VALUE`.
        var mode: String
        /// `COUNT`, `MINUTES`, `KM`, `STEPS` - nur bei `VALUE`.
        var unit: String?

        static let check = Tracking(mode: "CHECK", unit: nil)
        var isValue: Bool { mode == "VALUE" }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(mode, forKey: .mode)
            if let unit { try c.encode(unit, forKey: .unit) }
        }
    }

    struct Rhythm: Codable, Hashable, Sendable {
        /// `DAILY`, `WEEKDAYS`, `TIMES_PER_WEEK`, `TIMES_PER_MONTH`, `INTERVAL`.
        var kind: String
        var weekdays: [Int]?
        var times: Int?
        var days: Int?

        static let daily = Rhythm(kind: "DAILY")

        init(kind: String, weekdays: [Int]? = nil, times: Int? = nil, days: Int? = nil) {
            self.kind = kind
            self.weekdays = weekdays
            self.times = times
            self.days = days
        }

        /// Nur die Felder, die zur Art gehoeren - ein `times` neben `DAILY`
        /// waere ein Widerspruch, den der Dienst nicht aufloesen muessen soll.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            switch kind {
            case "WEEKDAYS": try c.encode(weekdays ?? [], forKey: .weekdays)
            case "TIMES_PER_WEEK", "TIMES_PER_MONTH": try c.encode(times ?? 1, forKey: .times)
            case "INTERVAL": try c.encode(days ?? 2, forKey: .days)
            default: break
            }
        }
    }

    struct Streak: Codable, Hashable, Sendable {
        var rhythm: Rhythm
        var groupStreak: Bool
    }

    struct Abstinence: Codable, Hashable, Sendable {
        var groupMode: Bool
    }

    struct Goal: Codable, Hashable, Sendable {
        var target: Double
        var start: CalendarDate?
        var deadline: CalendarDate
        /// `ENTRIES` oder `AMOUNT`.
        var counting: String
        /// `INDIVIDUAL` oder `TEAM`.
        var mode: String
    }

    struct Challenge: Codable, Hashable, Sendable {
        var start: CalendarDate
        var end: CalendarDate
        /// `MOST_ENTRIES`, `HIGHEST_SUM`, `FIRST_TO_TARGET`.
        var scoring: String
        var target: Double?
        var stake: String?
        /// `NONE`, `WEEKLY`, `MONTHLY`.
        var recurrence: String

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
            try c.encode(scoring, forKey: .scoring)
            try c.encode(scoring == "FIRST_TO_TARGET" ? target : nil, forKey: .target)
            try c.encode(stake, forKey: .stake)
            try c.encode(recurrence, forKey: .recurrence)
        }
    }

    struct Health: Codable, Hashable, Sendable {
        /// `STEPS`, `RUNNING_DISTANCE`, `WORKOUTS`, `WORKOUT_MINUTES`.
        var metric: String
    }

    struct Auto: Codable, Hashable, Sendable {
        /// `FOOD`, `STEPS_WEEKLY`, `FOCUS`.
        var source: String
        var weeklyStepGoal: Int?
        var focusMinutesGoal: Int?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(source, forKey: .source)
            try c.encode(weeklyStepGoal, forKey: .weeklyStepGoal)
            try c.encode(focusMinutesGoal, forKey: .focusMinutesGoal)
        }
    }

    var type: CohabitType
    var name: String
    var color: PaletteKey
    var timezone: String
    var tracking: Tracking
    var photoRequired: Bool
    var backfillHours: Int
    var reminderTime: String?
    var membersCanInvite: Bool
    var streak: Streak?
    var abstinence: Abstinence?
    var goal: Goal?
    var challenge: Challenge?
    var health: Health?
    var auto: Auto?

    /// Die erlaubten Nachtragsfristen in Stunden (Vertrag §2.2).
    static let backfillChoices = [0, 24, 48, 72, 168, 336]

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(timezone, forKey: .timezone)
        try c.encode(tracking, forKey: .tracking)
        try c.encode(photoRequired, forKey: .photoRequired)
        try c.encode(backfillHours, forKey: .backfillHours)
        try c.encode(reminderTime, forKey: .reminderTime)
        try c.encode(membersCanInvite, forKey: .membersCanInvite)
        try c.encode(streak, forKey: .streak)
        try c.encode(abstinence, forKey: .abstinence)
        try c.encode(goal, forKey: .goal)
        try c.encode(challenge, forKey: .challenge)
        try c.encode(health, forKey: .health)
        try c.encode(auto, forKey: .auto)
    }

    /// Ein frisches Co-Habit eines Typs mit den Vorgaben des Vertrags.
    static func draft(_ type: CohabitType, today: CalendarDate = .today(in: TimeZone(identifier: "Europe/Berlin") ?? .current)) -> CohabitConfig {
        var config = CohabitConfig(
            type: type, name: "", color: type.palette, timezone: "Europe/Berlin",
            tracking: .check, photoRequired: false, backfillHours: 48, reminderTime: nil,
            membersCanInvite: false)
        switch type {
        case .streak:
            config.streak = Streak(rhythm: .daily, groupStreak: false)
        case .abstinence:
            config.abstinence = Abstinence(groupMode: false)
        case .goal:
            config.goal = Goal(target: 10, start: today, deadline: today.adding(days: 30),
                               counting: "ENTRIES", mode: "TEAM")
        case .challenge:
            config.challenge = Challenge(start: today, end: today.adding(days: 30),
                                         scoring: "MOST_ENTRIES", target: nil, stake: nil,
                                         recurrence: "NONE")
        }
        return config
    }
}

/// `POST /cohabits`: die Einstellungen plus, wer gleich eingeladen wird.
struct CreateCohabitRequest: Encodable, Sendable {
    let config: CohabitConfig
    let invitePersonIds: [String]

    func encode(to encoder: Encoder) throws {
        try config.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(invitePersonIds, forKey: .invitePersonIds)
    }

    private enum Keys: String, CodingKey { case invitePersonIds }
}

/// `PUT /cohabits/{id}`: dieselben Einstellungen ohne `type` - der ist nach
/// dem Anlegen unveraenderlich (Vertrag §2.2).
struct UpdateCohabitRequest: Encodable, Sendable {
    let config: CohabitConfig

    func encode(to encoder: Encoder) throws {
        try config.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        // Der Typ bleibt drin, aber unveraendert - so sieht der Dienst, dass
        // nichts umgestellt werden soll, und muss keinen fehlenden Schluessel deuten.
        try c.encode(config.type, forKey: .type)
    }

    private enum Keys: String, CodingKey { case type }
}

// MARK: - Anfragen

/// Ein Eintrag. Die Kennung vergibt die App - noch einmal geschickt (aus dem
/// Postausgang) antwortet der Dienst mit dem bestehenden Eintrag, nichts
/// entsteht doppelt.
struct CheckinRequest: Codable, Hashable, Sendable {
    let id: String
    let kind: CheckinKind
    let date: CalendarDate?
    var value: Double?
    var note: String?
    var photoId: String?
    var caption: String?

    init(id: String = UUID().uuidString.lowercased(), kind: CheckinKind = .done, date: CalendarDate? = nil,
         value: Double? = nil, note: String? = nil, photoId: String? = nil, caption: String? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.value = value
        self.note = note
        self.photoId = photoId
        self.caption = caption
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(date, forKey: .date)
        try c.encode(value, forKey: .value)
        try c.encode(note, forKey: .note)
        try c.encode(photoId, forKey: .photoId)
        try c.encode(caption, forKey: .caption)
    }
}

struct CheckinUpdate: Codable, Hashable, Sendable {
    var value: Double?
    var note: String?
    var caption: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(note, forKey: .note)
        try c.encode(caption, forKey: .caption)
    }
}

struct MessageRequest: Codable, Hashable, Sendable {
    let id: String
    var text: String?
    var photoId: String?

    init(id: String = UUID().uuidString.lowercased(), text: String?, photoId: String? = nil) {
        self.id = id
        self.text = text
        self.photoId = photoId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(photoId, forKey: .photoId)
    }
}

struct ReactionRequest: Codable, Hashable, Sendable {
    let target: String
    let reaction: ReactionKind
}

/// Ein Haken (Aufbauen) bzw. Rueckfall (Lassen) aus der klassischen Liste
/// (`POST /classic/habits/{id}/marks`). Die Kennung vergibt die App - dieselbe
/// noch einmal legt nichts doppelt an, deshalb darf er in den Postausgang.
///
/// Steht hier und nicht bei der Liste in `coHabit/Classic/`, weil der
/// Postausgang ihn speichert und die Kachel dieselbe Datei liest und neu
/// schreibt: einen Auftrag, den sie nicht dekodieren kann, verwuerfe sie samt
/// allen anderen.
struct ClassicMarkRequest: Codable, Hashable, Sendable {
    let date: CalendarDate
    /// 8 bis 64 Zeichen aus `[A-Za-z0-9-]` - eine klein geschriebene UUID passt.
    let id: String

    init(date: CalendarDate, id: String = UUID().uuidString.lowercased()) {
        self.date = date
        self.id = id
    }

    /// Hier, damit die Liste und das Nachsenden denselben Pfad schicken.
    static func path(habitId: String) -> String {
        "/classic/habits/\(habitId)/marks"
    }

    static func path(habitId: String, date: CalendarDate) -> String {
        "/classic/habits/\(habitId)/marks/\(date.iso)"
    }
}

// MARK: - Die Kachel (§3.7)

struct WidgetData: Codable, Hashable, Sendable {

    struct Item: Codable, Hashable, Sendable, Identifiable {
        let ref: CohabitRef
        var value: String
        var unit: String
        var sub: String
        var status: CohabitStatus
        var statusText: String
        let photoRequired: Bool
        var quickCheckIn: Bool
        var id: String { ref.id }
    }

    struct ChallengeEntry: Codable, Hashable, Sendable, Identifiable {
        let rank: Int
        let name: String
        let score: Double
        let me: Bool
        var id: String { "\(rank)-\(name)" }
    }

    struct ChallengeBoard: Codable, Hashable, Sendable {
        let ref: CohabitRef
        let endsText: String?
        let myRank: Int?
        let leaderboard: [ChallengeEntry]
    }

    struct TeamGoal: Codable, Hashable, Sendable {
        let ref: CohabitRef
        let percent: Int
    }

    struct OpenStreak: Codable, Hashable, Sendable {
        let ref: CohabitRef
        let text: String
    }

    let generatedAt: Date?
    var openCount: Int
    var cohabits: [Item]
    let challenge: ChallengeBoard?
    let teamGoal: TeamGoal?
    var openStreak: OpenStreak?

    /// Die eigene Aktion sofort zeigen (Vertrag §5.5: „lokal übernehmen, dann
    /// neu laden"). Nur der Zustand „heute erledigt" - Serie und Quote kennt
    /// erst der Dienst, die kommen mit dem naechsten Laden.
    func markingDone(_ cohabitId: String) -> WidgetData {
        var copy = self
        guard let index = copy.cohabits.firstIndex(where: { $0.ref.id == cohabitId }) else { return copy }
        let wasOpen = copy.cohabits[index].status == .open
        copy.cohabits[index].status = .done
        copy.cohabits[index].statusText = "erledigt"
        copy.cohabits[index].quickCheckIn = false
        if wasOpen { copy.openCount = max(0, copy.openCount - 1) }
        if copy.openStreak?.ref.id == cohabitId { copy.openStreak = nil }
        return copy
    }
}
