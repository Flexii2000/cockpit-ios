import Foundation

// Freunde und Serien beim Weight Tracker (Vertrag §10), abgeschrieben aus den
// Records unter `../weight-app/…/friends/dto/`. Freunde sehen voneinander nur
// ja/nein je Serie und Tag, die Schritte der Woche und Recovery und Strain als
// Farbe - mehr steht in diesen Formen nicht, und mehr zeigt die App nicht.

/// Die vier Serien einer Freundschaft.
enum StreakType: String, LenientEnum {
    /// Der Tag ist getrackt.
    case tracked = "TRACKED"
    /// Eiweiss ≥ Eiweissziel.
    case protein = "PROTEIN"
    /// Schritte ≥ Schrittziel.
    case steps = "STEPS"
    /// Getrackt und kcal ≤ kcal-Ziel.
    case kcal = "KCAL"
    case unknown
}

/// Wie eine Seite heute bei einer Serie steht.
enum StreakSide: String, LenientEnum {
    case done = "DONE"
    case open = "OPEN"
    /// Nur beim Kalorienziel: schon ueberschritten - die Serie steht trotzdem
    /// bis Mitternacht.
    case failed = "FAILED"
    /// Der Kalorienzaehler antwortet dem Dienst gerade nicht.
    case unknown = "UNKNOWN"
}

struct FriendStreak: Decodable, Equatable, Identifiable, Sendable {
    let type: StreakType
    /// Aufeinanderfolgende Tage, an denen beide erfuellt haben - heute dazu,
    /// sobald beide erfuellt haben.
    let current: Int
    let best: Int
    let me: StreakSide
    let friend: StreakSide
    /// Stand bis gestern ≥ 2 und heute steht mindestens eine Seite auf offen.
    let atRisk: Bool

    var id: String { type.rawValue }
}

/// Heute auf einen Blick, ohne Zahlen.
struct FriendToday: Decodable, Equatable, Sendable {
    var tracked = false
    var recoveryBand: RecoveryBand? = nil
    var strainBand: StrainBand? = nil
}

struct FriendStepsDay: Decodable, Equatable, Sendable {
    let date: CalendarDate
    var me: Int? = nil
    var friend: Int? = nil
}

struct FriendStepsTotals: Decodable, Equatable, Sendable {
    var me: Int? = nil
    var friend: Int? = nil
}

/// Die Schritte der laufenden Woche, Montag bis heute, und die Summen der Woche davor.
struct FriendSteps: Decodable, Equatable, Sendable {
    var weekStart: CalendarDate? = nil
    var days: [FriendStepsDay] = []
    var me: Int? = nil
    var friend: Int? = nil
    var lastWeek: FriendStepsTotals? = nil

    private enum CodingKeys: String, CodingKey { case weekStart, days, me, friend, lastWeek }

    init(weekStart: CalendarDate? = nil, days: [FriendStepsDay] = [], me: Int? = nil, friend: Int? = nil,
         lastWeek: FriendStepsTotals? = nil) {
        self.weekStart = weekStart
        self.days = days
        self.me = me
        self.friend = friend
        self.lastWeek = lastWeek
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decodeIfPresent(CalendarDate.self, forKey: .weekStart)
        days = try container.decodeIfPresent([FriendStepsDay].self, forKey: .days) ?? []
        me = try container.decodeIfPresent(Int.self, forKey: .me)
        friend = try container.decodeIfPresent(Int.self, forKey: .friend)
        lastWeek = try container.decodeIfPresent(FriendStepsTotals.self, forKey: .lastWeek)
    }
}

struct FriendNudge: Decodable, Equatable, Sendable {
    /// Ich habe heute noch nicht gestupst, und drueben ist noch etwas offen.
    var allowed = false
}

/// Eine Freundschaft, wie `GET /api/friends` sie liefert.
struct Friend: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    var person: String? = nil
    let name: String
    /// Ab diesem Tag zaehlen die Serien.
    var since: CalendarDate? = nil
    var today = FriendToday()
    /// Immer alle vier Arten, in der Reihenfolge Tracking, Eiweiss, Schritte, kcal.
    var streaks: [FriendStreak] = []
    var steps: FriendSteps? = nil
    var nudge = FriendNudge()

    private enum CodingKeys: String, CodingKey { case id, person, name, since, today, streaks, steps, nudge }

    init(id: String, person: String? = nil, name: String, since: CalendarDate? = nil,
         today: FriendToday = FriendToday(), streaks: [FriendStreak] = [], steps: FriendSteps? = nil,
         nudge: FriendNudge = FriendNudge()) {
        self.id = id
        self.person = person
        self.name = name
        self.since = since
        self.today = today
        self.streaks = streaks
        self.steps = steps
        self.nudge = nudge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        person = try container.decodeIfPresent(String.self, forKey: .person)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        since = try container.decodeIfPresent(CalendarDate.self, forKey: .since)
        today = try container.decodeIfPresent(FriendToday.self, forKey: .today) ?? FriendToday()
        streaks = try container.decodeIfPresent([FriendStreak].self, forKey: .streaks) ?? []
        steps = try container.decodeIfPresent(FriendSteps.self, forKey: .steps)
        nudge = try container.decodeIfPresent(FriendNudge.self, forKey: .nudge) ?? FriendNudge()
    }

    /// Die Serien, wie die Karte sie zeigt - ohne Arten, die diese App noch nicht kennt.
    var shownStreaks: [FriendStreak] { streaks.filter { FriendsFormat.label($0.type) != nil } }
}

/// Eine offene Einladung: acht Zeichen als „K7Q4-M2XD“, sieben Tage gueltig,
/// einmal einloesbar.
struct FriendInvite: Decodable, Equatable, Sendable {
    let code: String
    var expiresAt: Date? = nil
}

struct FriendsMe: Decodable, Equatable, Sendable {
    var person: String? = nil
    var name: String? = nil
}

/// `GET /api/friends`.
struct FriendsOverview: Decodable, Equatable, Sendable {
    var me: FriendsMe? = nil
    /// Nach Namen sortiert.
    var friends: [Friend] = []
    /// Die eigenen offenen Einladungen.
    var invites: [FriendInvite] = []

    private enum CodingKeys: String, CodingKey { case me, friends, invites }

    init(me: FriendsMe? = nil, friends: [Friend] = [], invites: [FriendInvite] = []) {
        self.me = me
        self.friends = friends
        self.invites = invites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        me = try container.decodeIfPresent(FriendsMe.self, forKey: .me)
        friends = try container.decodeIfPresent([Friend].self, forKey: .friends) ?? []
        invites = try container.decodeIfPresent([FriendInvite].self, forKey: .invites) ?? []
    }
}

/// `GET /api/streaks` - die Serien-Kachel im Dashboard.
struct StreakTile: Decodable, Equatable, Sendable {

    /// Die eigene Tracking-Serie, ohne Freundschaft.
    struct Tracking: Decodable, Equatable, Sendable {
        let current: Int
        var best: Int? = nil
        var todayDone: Bool? = nil
    }

    /// Die Freundes-Serie mit dem hoechsten Stand.
    struct TopFriend: Decodable, Equatable, Sendable {
        var friendshipId: String? = nil
        let name: String
        var type: StreakType? = nil
        let current: Int
        var atRisk: Bool? = nil
    }

    var tracking: Tracking? = nil
    /// `nil` ohne Freunde oder ohne laufende Serie.
    var topFriend: TopFriend? = nil
}

struct NudgeResult: Decodable, Equatable, Sendable {
    /// `false`: kein Geraet erreicht - der Stupser zaehlt trotzdem.
    let delivered: Bool
}

struct FriendAcceptRequest: Encodable, Sendable {
    let code: String
}
