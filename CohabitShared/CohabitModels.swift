import Foundation

// Die Formen der coHabit-API (Vertrag §3). Gerechnet wird ausschliesslich im
// Dienst: Serien, Quoten, Raenge und alle Texte der Kennzahlen kommen fertig
// an. Die App formatiert nur Datum und Uhrzeit.

/// Ein Aufzaehlungstyp, der unbekannte Werte nicht mit einem Dekodierfehler
/// quittiert. Kommt im Dienst ein neuer Wert dazu, soll nicht der ganze
/// Bildschirm leer bleiben - der Wert faellt auf `fallback`.
protocol LenientEnum: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    static var fallback: Self { get }
}

extension LenientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Gemeinsame Objekte (§3.0)

enum PaletteKey: String, LenientEnum, CaseIterable, Identifiable {
    case peach, mint, periwinkle, butter, rose, aqua
    static let fallback = PaletteKey.periwinkle
    var id: String { rawValue }
}

enum CohabitType: String, LenientEnum, CaseIterable, Identifiable {
    case streak = "STREAK"
    case abstinence = "ABSTINENCE"
    case goal = "GOAL"
    case challenge = "CHALLENGE"
    static let fallback = CohabitType.streak
    var id: String { rawValue }

    /// „Laufen · Streak" auf der Dashboard-Karte (Vertrag §5.2.1).
    var title: String {
        switch self {
        case .streak: "Streak"
        case .abstinence: "Abstinenz"
        case .goal: "Ziel"
        case .challenge: "Challenge"
        }
    }

    /// Die Farbe der Typkarte im Anlegen-Schritt 1.
    var palette: PaletteKey {
        switch self {
        case .streak: .peach
        case .abstinence: .mint
        case .goal: .periwinkle
        case .challenge: .butter
        }
    }
}

struct PersonView: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let username: String
    let initials: String
    let color: PaletteKey
    let avatarPhotoId: String?
}

struct CohabitRef: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let color: PaletteKey
    let type: CohabitType
}

/// Eine Reaktion samt allen, die sie gesetzt haben (Vertrag §2.7a): `reaction`
/// und `label` sind das Emoji, `people` in der Reihenfolge der Reaktionen.
/// Der Dienst sortiert nach `count` absteigend, bei Gleichstand nach der
/// fruehesten Reaktion.
///
/// Liest tolerant: ein aelterer Dienst schickt die festen Namen (`STARK` …)
/// und kein `people` - daraus wird das Emoji, das der Dienst heute dafuer setzt.
struct ReactionView: Codable, Hashable, Sendable {
    let reaction: String
    let label: String
    let count: Int
    let mine: Bool
    let people: [PersonView]

    init(reaction: String, label: String? = nil, count: Int, mine: Bool, people: [PersonView] = []) {
        self.reaction = reaction
        self.label = label ?? reaction
        self.count = count
        self.mine = mine
        self.people = people
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reaction = Emoji.fromService(try c.decode(String.self, forKey: .reaction))
        let label = try c.decodeIfPresent(String.self, forKey: .label)
        self.label = label.map(Emoji.fromService) ?? reaction
        count = try c.decode(Int.self, forKey: .count)
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        people = try c.decodeIfPresent([PersonView].self, forKey: .people) ?? []
    }
}

struct Headline: Codable, Hashable, Sendable {
    let value: String
    let unit: String
    let short: String
}

struct Seats: Codable, Hashable, Sendable {
    let used: Int
    let max: Int

    var free: Int { Swift.max(0, max - used) }
}

// MARK: - Ich, Profil (§3.2)

struct MeView: Codable, Hashable, Sendable {
    struct Counts: Codable, Hashable, Sendable {
        let cohabits: Int
        let friends: Int
        let wins: Int
    }

    let person: PersonView
    let isOwner: Bool
    let sources: [String]
    let counts: Counts
    let pendingInvitations: Int
    let incomingFriendRequests: Int
    let canLogout: Bool
    let createdAt: Date?
}

struct NotificationSettings: Codable, Hashable, Sendable {
    var checkins: Bool
    var photos: Bool
    var chat: Bool
    var nudges: Bool
    var invites: Bool
    var reminders: Bool
    var streakAtRisk: Bool
    var challengeEnd: Bool
}

struct AppLink: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let label: String
    let createdAt: Date?
    let lastUsedAt: Date?
}

struct CreatedAppLink: Codable, Hashable, Sendable {
    let id: String
    let label: String
    let setupUrl: String
    let token: String
}

// MARK: - Freunde (§3.3)

struct FriendRequest: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let from: PersonView
    let to: PersonView
    let createdAt: Date?
}

struct FriendsOverview: Codable, Hashable, Sendable {
    let friends: [PersonView]
    let incoming: [FriendRequest]
    let outgoing: [FriendRequest]
}

enum PersonRelation: String, LenientEnum {
    case friend = "FRIEND"
    case requestSent = "REQUEST_SENT"
    case requestReceived = "REQUEST_RECEIVED"
    case none = "NONE"
    case selfPerson = "SELF"
    static let fallback = PersonRelation.none
}

struct PersonSearchResult: Codable, Hashable, Sendable, Identifiable {
    let person: PersonView
    let relation: PersonRelation
    var id: String { person.id }
}

/// Einladungs- und Freundes-Link.
struct LinkInfo: Codable, Hashable, Sendable {
    let url: String
    let code: String
    let expiresAt: Date?
}

// MARK: - Co-Habits (§3.4)

enum CohabitStatus: String, LenientEnum {
    case open = "OPEN"
    case done = "DONE"
    case running = "RUNNING"
    case unavailable = "UNAVAILABLE"
    static let fallback = CohabitStatus.running
}

enum TodaySection: String, LenientEnum {
    case openToday = "OPEN_TODAY"
    case running = "RUNNING"
    static let fallback = TodaySection.running
}

struct SummaryProgress: Codable, Hashable, Sendable {
    let done: Double
    let goal: Double
    let fraction: Double
}

struct SummaryRank: Codable, Hashable, Sendable {
    let mine: Int
    let of: Int
    let gapText: String?
}

struct CohabitSummary: Codable, Hashable, Sendable, Identifiable {
    let ref: CohabitRef
    let archived: Bool
    let headline: Headline
    let typeLine: String
    let subline: String?
    let listLine: String?
    let status: CohabitStatus
    let section: TodaySection
    let unavailableText: String?
    let canCheckIn: Bool
    let photoRequired: Bool
    let valueUnit: String?
    let checkInLabel: String?
    /// Laufpunkte (Vertrag §2.6a): das Eintragsblatt fragt Dauer und Distanz
    /// statt eines Werts. Fehlt bei einem aelteren Dienst - dann `nil`.
    let runEntry: Bool?
    let members: [PersonView]
    let memberCount: Int
    let doneTodayBy: [String]
    let progress: SummaryProgress?
    let rank: SummaryRank?
    let unreadMessages: Int

    var id: String { ref.id }
    var isRunEntry: Bool { runEntry == true }
}

enum MemberRole: String, LenientEnum {
    case admin = "ADMIN"
    case member = "MEMBER"
    static let fallback = MemberRole.member
}

struct Member: Codable, Hashable, Sendable, Identifiable {
    let person: PersonView
    let role: MemberRole
    let state: String
    let joinedAt: Date?
    var id: String { person.id }
}

/// Zustand einer Zelle im Wochenraster (Vertrag §3.4, StreakBlock).
enum WeekCell: String, LenientEnum {
    case done = "DONE"
    case missed = "MISSED"
    case open = "OPEN"
    case paused = "PAUSED"
    case future = "FUTURE"
    case notDue = "NOT_DUE"
    case beforeJoin = "BEFORE_JOIN"
    static let fallback = WeekCell.future
}

struct StreakBlock: Codable, Hashable, Sendable {
    struct Week: Codable, Hashable, Sendable {
        struct Row: Codable, Hashable, Sendable, Identifiable {
            let person: PersonView
            let cells: [WeekCell]
            var id: String { person.id }
        }

        let days: [CalendarDate]
        let todayIndex: Int?
        let rows: [Row]
    }

    struct Record: Codable, Hashable, Sendable {
        let value: Int
        let short: String
        let person: PersonView?
    }

    struct Group: Codable, Hashable, Sendable {
        let current: Int
        let unitLabel: String
    }

    let current: Int
    let unit: String
    let unitLabel: String
    let atRisk: Bool
    let remainingText: String?
    let week: Week?
    let fulfillmentRate: Int?
    let record: Record?
    let group: Group?
}

struct AbstinenceBlock: Codable, Hashable, Sendable {
    struct MemberDays: Codable, Hashable, Sendable, Identifiable {
        let person: PersonView
        let days: Int
        let newPersonalRecord: Bool
        var id: String { person.id }
    }

    struct Series: Codable, Hashable, Sendable {
        let label: String
        let days: Int
        let current: Bool
    }

    struct Group: Codable, Hashable, Sendable {
        let days: Int
    }

    let currentDays: Int
    let record: Int
    let toRecordText: String?
    let members: [MemberDays]
    let series: [Series]
    let group: Group?
}

struct GoalBlock: Codable, Hashable, Sendable {
    struct Contribution: Codable, Hashable, Sendable, Identifiable {
        let person: PersonView
        let value: Double
        let valueText: String
        let fraction: Double
        var id: String { person.id }
    }

    struct Finished: Codable, Hashable, Sendable {
        let reached: Bool
        let text: String
    }

    let target: Double
    let targetText: String
    let unitLabel: String
    let deadline: CalendarDate
    let counting: String
    let mode: String
    let typeLine: String
    let total: Double
    let totalText: String
    let percent: Int
    let planDelta: Double?
    let planDeltaText: String?
    let remainingDays: Int?
    let remainingText: String?
    let contributions: [Contribution]
    let finished: Finished?
}

struct LeaderboardEntry: Codable, Hashable, Sendable, Identifiable {
    let rank: Int
    let person: PersonView
    let score: Double
    let scoreText: String
    let fraction: Double
    var id: String { person.id }
}

struct ChallengeBlock: Codable, Hashable, Sendable {
    struct PastRound: Codable, Hashable, Sendable, Identifiable {
        let label: String
        let winners: [PersonView]
        var id: String { label }
    }

    let round: Int
    let start: CalendarDate
    let end: CalendarDate
    let endsAt: Date?
    let endsInText: String?
    let periodLabel: String?
    let scoring: String
    let scoringText: String
    let target: Double?
    let stake: String?
    let recurrence: String
    let recurrenceText: String?
    let myRank: Int?
    let leaderboard: [LeaderboardEntry]
    let pastRounds: [PastRound]
    let finished: Bool
}

struct HealthInfo: Codable, Hashable, Sendable {
    let metric: String
    let label: String
    let consent: Bool
    let lastSyncAt: Date?
    let shareText: String?
    /// `DEVICE`: die App liest Apple Health und schickt die Tageswerte.
    /// `HEALTHY`: der Dienst holt sie selbst aus dem Kalorienzaehler (kcal) -
    /// die App fragt dann nichts aus Apple Health ab. Fehlt das Feld (aelterer
    /// Dienst), ist es DEVICE.
    let source: String?

    var isFromHealthy: Bool { source?.uppercased() == "HEALTHY" }
}

struct Pause: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let from: CalendarDate
    let to: CalendarDate
}

struct MySettings: Codable, Hashable, Sendable {
    var muted: Bool
    var checkins: Bool?
    var chat: Bool?
    var shareBreaks: Bool
    var healthConsent: Bool

    /// `checkins`/`chat` = null heisst „wie global" - das muss als null
    /// ankommen, nicht als fehlender Schluessel.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(muted, forKey: .muted)
        try c.encode(checkins, forKey: .checkins)
        try c.encode(chat, forKey: .chat)
        try c.encode(shareBreaks, forKey: .shareBreaks)
        try c.encode(healthConsent, forKey: .healthConsent)
    }
}

struct PodiumEntry: Codable, Hashable, Sendable, Identifiable {
    let rank: Int
    let person: PersonView
    let score: Double?
    let scoreText: String?
    var id: String { person.id }
}

struct FinishedDialog: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let podium: [PodiumEntry]
    let stakeText: String?
    let nextText: String?
    /// Die Systemmeldung zum Ende, auf die „Gratulieren" 💪 setzt -
    /// liefert der Dienst zusaetzlich zum Vertrag mit.
    let reactionTarget: String?

    var isChallenge: Bool { kind.uppercased() == "CHALLENGE" }
}

struct CohabitDetail: Codable, Hashable, Sendable, Identifiable {
    let summary: CohabitSummary
    let config: CohabitConfig
    let createdBy: String?
    let createdAt: Date?
    let myRole: MemberRole
    let canInvite: Bool
    let seats: Seats
    let members: [Member]
    let rules: [String]
    let streak: StreakBlock?
    let abstinence: AbstinenceBlock?
    let goal: GoalBlock?
    let challenge: ChallengeBlock?
    let health: HealthInfo?
    let myCheckins: [Checkin]
    let backfillFrom: CalendarDate?
    let myPauses: [Pause]
    let mySettings: MySettings
    let unreadMessages: Int
    let dialog: FinishedDialog?

    var id: String { summary.ref.id }
    var ref: CohabitRef { summary.ref }
    var isAdmin: Bool { myRole == .admin }
}

struct InvitationCohabit: Codable, Hashable, Sendable {
    let ref: CohabitRef
    let typeLine: String
    let rules: [String]
    let members: [PersonView]
    let seats: Seats
}

struct InvitationView: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let from: PersonView
    let createdAt: Date?
    let cohabit: InvitationCohabit
}

struct InviteCandidates: Codable, Hashable, Sendable {
    struct Candidate: Codable, Hashable, Sendable, Identifiable {
        let person: PersonView
        let status: String
        var id: String { person.id }
        var isMember: Bool { status == "MEMBER" }
        var isInvited: Bool { status == "INVITED" }
    }

    let seats: Seats
    let canInvite: Bool
    let people: [Candidate]
}

// MARK: - Oeffentlich (§3.1)

struct InviteLinkPreview: Codable, Hashable, Sendable {
    let kind: String
    let from: PersonView
    let cohabit: InvitationCohabit?
    let full: Bool

    var isFriendLink: Bool { kind.uppercased() == "FRIEND" }
}

struct AcceptResult: Codable, Hashable, Sendable {
    let me: MeView
    let token: String?
    let setupUrl: String?
    let cohabitId: String?
}

// MARK: - Eintraege (§3.5)

enum CheckinKind: String, LenientEnum {
    case done = "DONE"
    case `break` = "BREAK"
    static let fallback = CheckinKind.done
}

struct Checkin: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let cohabitId: String
    let person: PersonView
    let kind: CheckinKind
    let date: CalendarDate
    let createdAt: Date?
    let value: Double?
    let valueText: String?
    let note: String?
    let photoId: String?
    let caption: String?
    let source: String
    let editable: Bool
    /// Nur bei Laufpunkten (Vertrag §2.6a), sonst `nil` - auch bei einem
    /// aelteren Dienst, der das Feld nicht kennt.
    let run: CheckinRun?
    /// Alle Beweisfotos (bis zu vier, Vertrag §2.3a), das erste ist `photoId`.
    /// Ein aelterer Dienst kennt nur `photoId` - dann `nil`, siehe `photos`.
    let photoIds: [String]?

    /// Die Fotos in Anzeige-Reihenfolge - auch von einem Dienst ohne `photoIds`.
    var photos: [String] { PhotoList.of(photoId, photoIds) }
}

/// Mehrere Beweisfotos (Vertrag §2.3a): `photoIds` ist die ganze Reihe, das
/// erste steht zusaetzlich in `photoId` - und nur dort bei einem aelteren
/// Dienst oder Eintrag.
enum PhotoList {
    /// Hoechstens so viele Fotos je Eintrag.
    static let maxCount = 4

    static func of(_ photoId: String?, _ photoIds: [String]?) -> [String] {
        if let photoIds, !photoIds.isEmpty { return photoIds }
        return photoId.map { [$0] } ?? []
    }
}

/// Ein Lauf mit seinen Punkten - alles fertig vom Dienst, die App rechnet
/// nichts nach. Jedes Feld optional: ein fehlendes soll nicht den ganzen
/// Eintrag (und mit ihm die Detailseite) unlesbar machen.
struct CheckinRun: Codable, Hashable, Sendable {
    let durationMinutes: Int?
    let distanceKm: Double?
    /// „6:02 min/km"
    let paceText: String?
    let points: Int?
    /// „+20 P"
    let pointsText: String?
    /// „Basis 10 · Distanz 5 · Dauer 5"
    let breakdownText: String?
}

struct CheckinResult: Codable, Hashable, Sendable {
    let checkin: Checkin
    let cohabit: CohabitDetail
}

// MARK: - Chat (§3.6)

enum MessageKind: String, LenientEnum {
    case text = "TEXT"
    case photo = "PHOTO"
    /// Ein GIF aus der Suche (KLIPY, Vertrag §2.7a) - steht in `gif`.
    case gif = "GIF"
    case checkin = "CHECKIN"
    case system = "SYSTEM"
    static let fallback = MessageKind.system
}

struct Message: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let cohabitId: String
    let kind: MessageKind
    let author: PersonView?
    let mine: Bool
    let createdAt: Date
    let text: String?
    let photoId: String?
    let checkin: Checkin?
    let systemText: String?
    let reactionTarget: String
    let reactions: [ReactionView]
    let deleted: Bool
    /// Check-in-Post: alle Fotos des Eintrags; Foto-Nachricht: das eine.
    let photoIds: [String]?
    /// Bei `kind: GIF` das GIF aus der Suche.
    let gif: GifView?
    /// Ein eigenes GIF (`kind: PHOTO`): `GET /photos/{id}?size=full` liefert
    /// dann `image/gif`. Fehlt bei einem aelteren Dienst.
    let photoAnimated: Bool?

    var isAnimatedPhoto: Bool { photoAnimated == true }

    /// Die Fotos des Posts - bei einem Check-in-Post notfalls aus dem Eintrag.
    var photos: [String] {
        let own = PhotoList.of(photoId, photoIds)
        return own.isEmpty ? (checkin?.photos ?? []) : own
    }
}

struct MessagesPage: Codable, Hashable, Sendable {
    let messages: [Message]
    let hasMore: Bool

    init(messages: [Message], hasMore: Bool) {
        self.messages = messages
        self.hasMore = hasMore
    }

    /// `hasMore` fehlt bei `?after=` womoeglich - dann gibt es nichts Aelteres zu holen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decode([Message].self, forKey: .messages)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

struct ReactionsResult: Codable, Hashable, Sendable {
    let reactions: [ReactionView]
}

struct UnreadResult: Codable, Hashable, Sendable {
    let unread: Int
}

// MARK: - Heute, Timeline, Statistik (§3.7)

struct Nudge: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let from: PersonView
    let cohabit: CohabitRef
    let text: String
    let createdAt: Date?
}

struct NewPhotos: Codable, Hashable, Sendable {
    let count: Int
    let photoIds: [String]
}

struct Today: Codable, Hashable, Sendable {
    let date: CalendarDate
    let openCount: Int
    let headline: String
    let nudges: [Nudge]
    let newPhotos: NewPhotos?
    let invitations: [InvitationView]
    let cohabits: [CohabitSummary]
}

enum TimelineKind: String, LenientEnum {
    case checkin = "CHECKIN"
    case photoCheckin = "PHOTO_CHECKIN"
    case health = "HEALTH"
    case milestone = "MILESTONE"
    case newBest = "NEW_BEST"
    case challengeEnded = "CHALLENGE_ENDED"
    case goalFinished = "GOAL_FINISHED"
    case `break` = "BREAK"
    static let fallback = TimelineKind.checkin
}

struct TimelineItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let day: CalendarDate
    let at: Date?
    let cohabit: CohabitRef
    let kind: TimelineKind
    let person: PersonView?
    let title: String
    let subtitle: String?
    let photoId: String?
    let caption: String?
    let reactionTarget: String
    let reactions: [ReactionView]
    let canReply: Bool
    /// Alle Beweisfotos des Eintrags, das erste ist `photoId`.
    let photoIds: [String]?

    var photos: [String] { PhotoList.of(photoId, photoIds) }
}

struct TimelinePage: Codable, Hashable, Sendable {
    let items: [TimelineItem]
    let hasMore: Bool
}

enum StatsRange: String, LenientEnum, CaseIterable, Identifiable {
    case week = "WEEK"
    case month = "MONTH"
    case year = "YEAR"
    static let fallback = StatsRange.month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Woche"
        case .month: "Monat"
        case .year: "Jahr"
        }
    }
}

struct Stats: Codable, Hashable, Sendable {
    struct LongestStreak: Codable, Hashable, Sendable {
        let short: String
        let cohabit: CohabitRef
    }

    struct HeatDay: Codable, Hashable, Sendable {
        let date: CalendarDate
        let count: Int
        let level: Int
    }

    struct Heatmap: Codable, Hashable, Sendable {
        let from: CalendarDate
        let to: CalendarDate
        let days: [HeatDay]
    }

    struct Row: Codable, Hashable, Sendable, Identifiable {
        let ref: CohabitRef
        let progressText: String
        let fraction: Double
        var id: String { ref.id }
    }

    let range: StatsRange
    let label: String
    let fulfillmentRate: Int?
    let longestStreak: LongestStreak?
    let heatmap: Heatmap
    let cohabits: [Row]
}

struct PhotoUpload: Codable, Hashable, Sendable {
    let id: String
    let width: Int?
    let height: Int?
    /// Ein GIF mit mehr als einem Bild, unveraendert abgelegt (Vertrag §2.7a).
    let animated: Bool?
}
