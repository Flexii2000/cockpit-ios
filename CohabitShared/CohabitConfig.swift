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
        /// `COUNT`, `MINUTES`, `KM`, `STEPS`, `KCAL` - nur bei `VALUE`.
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
        /// `ChallengeScoring` - als Text, siehe dort.
        var scoring: String
        var target: Double?
        var stake: String?
        /// `NONE`, `WEEKLY`, `MONTHLY`.
        var recurrence: String
        /// Nur bei Laufpunkten (Vertrag §2.6a), sonst `nil`.
        var run: RunScoring? = nil

        var isRunPoints: Bool { scoring == ChallengeScoring.runPoints }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
            try c.encode(scoring, forKey: .scoring)
            try c.encode(scoring == ChallengeScoring.firstToTarget ? target : nil, forKey: .target)
            try c.encode(stake, forKey: .stake)
            try c.encode(recurrence, forKey: .recurrence)
            // Ausdruecklich die Werte, die das Formular zeigt - auch wenn sie
            // die Vorgaben sind; bei jeder anderen Wertung null.
            try c.encode(isRunPoints ? (run ?? .defaults) : nil, forKey: .run)
        }
    }

    struct Health: Codable, Hashable, Sendable {
        /// `STEPS`, `RUNNING_DISTANCE`, `WORKOUTS`, `WORKOUT_MINUTES` aus Apple
        /// Health; `KCAL` aus Healthy (holt der Dienst selbst).
        var metric: String
    }

    struct Auto: Codable, Hashable, Sendable {
        /// `FOOD`, `FOOD_TARGET_WEEKLY` (seit 2026-10-01: das kcal-Ziel im
        /// Wochenmittel, ohne eigene Ziele), `STEPS_WEEKLY`, `FOCUS` - und was
        /// der Dienst spaeter noch erfindet: als Text, damit nichts kippt.
        var source: String
        var weeklyStepGoal: Int?
        /// FOCUS: Minuten je Tag oder je Woche (`focusPeriod`).
        var focusMinutesGoal: Int?
        /// FOCUS: nur Baeume dieser Wald-Kategorie; nil = alle Baeume.
        var focusCategoryId: String? = nil
        /// Ihr Name - traegt der Dienst ein, gesendet wird er nicht.
        var focusCategoryName: String? = nil
        /// FOCUS: `DAY` (Vorgabe) oder `WEEK`.
        var focusPeriod: String? = nil

        /// Fokus-Minuten je Woche statt je Tag.
        var isWeeklyFocus: Bool { source == "FOCUS" && focusPeriod == "WEEK" }

        /// Zaehlt je Woche (Montag bis Sonntag) statt je Tag.
        var isWeekly: Bool { source == "STEPS_WEEKLY" || source == "FOOD_TARGET_WEEKLY" || isWeeklyFocus }

        /// Kategorie und Zeitraum stehen immer im Rumpf: der Dienst liest
        /// beim Bearbeiten ein fehlendes Feld als „alle Baeume" bzw. „je Tag".
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(source, forKey: .source)
            try c.encode(weeklyStepGoal, forKey: .weeklyStepGoal)
            try c.encode(focusMinutesGoal, forKey: .focusMinutesGoal)
            try c.encode(source == "FOCUS" ? focusCategoryId : nil, forKey: .focusCategoryId)
            try c.encode(source == "FOCUS" ? (focusPeriod ?? "DAY") : nil, forKey: .focusPeriod)
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
            type: type, name: "", color: TypeColorSlot(type).defaultColor, timezone: "Europe/Berlin",
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

/// Die Wertungen einer Challenge (Vertrag §2.6, §2.6a).
///
/// Bewusst Text und kein `LenientEnum`: ein unbekannter Wert fiele dort auf
/// eine bekannte Wertung zurueck - und das Bearbeiten-Formular schickte beim
/// Sichern diese statt der echten zurueck. Als Text geht er unveraendert hin
/// und her.
enum ChallengeScoring {
    static let mostEntries = "MOST_ENTRIES"
    static let highestSum = "HIGHEST_SUM"
    static let firstToTarget = "FIRST_TO_TARGET"
    /// Punkte aus Dauer und Distanz je Lauf (seit 2026-10-03).
    static let runPoints = "RUN_POINTS"
}

/// Die Gewichte einer Lauf-Challenge (`challenge.run`, Vertrag §2.6a).
/// Gerechnet wird im Dienst - die App zeigt und schickt nur die Zahlen.
///
/// Fehlt ein Feld, gilt die Vorgabe; so dekodiert es auch hier. `nil` steht
/// nur, solange im Formular ein Feld leer oder unlesbar ist - dann laesst
/// sich nicht sichern (`problem`).
struct RunScoring: Codable, Hashable, Sendable {
    /// Basis je Lauf (hoechstens einmal je Person und Tag), 0–1000 P.
    var basePoints: Int?
    /// Punkte je volle km, 0–1000.
    var pointsPerKm: Int?
    /// 1 Punkt je volle N Minuten, 1–600.
    var minutesPerPoint: Int?
    /// Die Basis erst ab N Minuten, 0–600.
    var baseMinMinutes: Int?
    /// Die Ø-Pace muss schneller sein als N Sekunden je km, 60–3600.
    var paceLimitSeconds: Int?

    static let defaults = RunScoring(basePoints: 10, pointsPerKm: 1, minutesPerPoint: 6,
                                     baseMinMinutes: 20, paceLimitSeconds: 480)

    private enum CodingKeys: String, CodingKey {
        case basePoints, pointsPerKm, minutesPerPoint, baseMinMinutes, paceLimitSeconds
    }

    init(basePoints: Int?, pointsPerKm: Int?, minutesPerPoint: Int?, baseMinMinutes: Int?, paceLimitSeconds: Int?) {
        self.basePoints = basePoints
        self.pointsPerKm = pointsPerKm
        self.minutesPerPoint = minutesPerPoint
        self.baseMinMinutes = baseMinMinutes
        self.paceLimitSeconds = paceLimitSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        basePoints = try c.decodeIfPresent(Int.self, forKey: .basePoints) ?? d.basePoints
        pointsPerKm = try c.decodeIfPresent(Int.self, forKey: .pointsPerKm) ?? d.pointsPerKm
        minutesPerPoint = try c.decodeIfPresent(Int.self, forKey: .minutesPerPoint) ?? d.minutesPerPoint
        baseMinMinutes = try c.decodeIfPresent(Int.self, forKey: .baseMinMinutes) ?? d.baseMinMinutes
        paceLimitSeconds = try c.decodeIfPresent(Int.self, forKey: .paceLimitSeconds) ?? d.paceLimitSeconds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(basePoints, forKey: .basePoints)
        try c.encode(pointsPerKm, forKey: .pointsPerKm)
        try c.encode(minutesPerPoint, forKey: .minutesPerPoint)
        try c.encode(baseMinMinutes, forKey: .baseMinMinutes)
        try c.encode(paceLimitSeconds, forKey: .paceLimitSeconds)
    }

    /// Was dem Sichern im Weg steht - die Bereiche aus dem Vertrag, damit
    /// ein Tippfehler nicht erst nach „Co-Habit starten" auffaellt.
    var problem: String? {
        if !Self.fits(basePoints, 0...1000) { return "Basis fehlt" }
        if !Self.fits(pointsPerKm, 0...1000) { return "Punkte je km fehlen" }
        if !Self.fits(minutesPerPoint, 1...600) { return "Minuten je Punkt fehlen" }
        if !Self.fits(baseMinMinutes, 0...600) { return "Mindestdauer fehlt" }
        if !Self.fits(paceLimitSeconds, 60...3600) { return "Pace-Grenze fehlt" }
        return nil
    }

    private static func fits(_ value: Int?, _ range: ClosedRange<Int>) -> Bool {
        value.map(range.contains) ?? false
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
///
/// Liegt auch im Postausgang (App-Gruppe): neue Felder sind optional, damit
/// ein Auftrag aus einer aelteren Fassung weiter dekodiert.
struct CheckinRequest: Codable, Hashable, Sendable {
    let id: String
    let kind: CheckinKind
    let date: CalendarDate?
    var value: Double?
    var note: String?
    /// Nur noch aus Postausgang-Auftraegen der Fassung mit einem Foto - neue
    /// tragen `photoIds`; gesendet wird beides aus `photos`.
    var photoId: String?
    var caption: String?
    /// Ein Lauf (Laufpunkte, Vertrag §2.6a): ganze Minuten und km - bei
    /// `runEntry` Pflicht, sonst ignoriert der Dienst beide.
    var durationMinutes: Int?
    var distanceKm: Double?
    /// Die Beweisfotos in Anzeige-Reihenfolge (Vertrag §2.3a, bis zu vier).
    var photoIds: [String]?

    init(id: String = UUID().uuidString.lowercased(), kind: CheckinKind = .done, date: CalendarDate? = nil,
         value: Double? = nil, note: String? = nil, photoId: String? = nil, caption: String? = nil,
         durationMinutes: Int? = nil, distanceKm: Double? = nil, photoIds: [String]? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.value = value
        self.note = note
        self.photoId = photoId
        self.caption = caption
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.photoIds = photoIds
    }

    /// Alle Fotos - auch aus einem alten Auftrag, der nur `photoId` kennt.
    var photos: [String] { PhotoList.of(photoId, photoIds) }

    /// Ein hochgeladenes Foto hinten anhaengen - die Reihenfolge ist die der
    /// Anzeige, und hochgeladen wird der Reihe nach.
    mutating func appendPhoto(_ id: String) {
        photoIds = photos + [id]
        photoId = nil
    }

    func encode(to encoder: Encoder) throws {
        let photos = photos
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(date, forKey: .date)
        try c.encode(value, forKey: .value)
        try c.encode(note, forKey: .note)
        // Das erste auch einzeln: so versteht ein Dienst ohne `photoIds`
        // wenigstens das.
        try c.encode(photos.first, forKey: .photoId)
        try c.encode(photos.isEmpty ? nil : photos, forKey: .photoIds)
        try c.encode(caption, forKey: .caption)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(distanceKm, forKey: .distanceKm)
    }

    /// „5,8 km in 35 Min." - damit eine Ablehnung beim Nachsenden sagt,
    /// welcher Lauf gemeint ist; die Eingaben sind dann weg.
    var runText: String? {
        guard let durationMinutes, let distanceKm else { return nil }
        let km = distanceKm.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
        return "\(km) km in \(durationMinutes) Min."
    }
}

/// `PUT …/checkins/{id}`. Bei den Lauf-Feldern und `photoIds` heisst `null`
/// „unveraendert"; eine Liste ist der neue Satz Fotos (auch leer).
struct CheckinUpdate: Codable, Hashable, Sendable {
    var value: Double?
    var note: String?
    var caption: String?
    var durationMinutes: Int? = nil
    var distanceKm: Double? = nil
    var photoIds: [String]? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(note, forKey: .note)
        try c.encode(caption, forKey: .caption)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(distanceKm, forKey: .distanceKm)
        try c.encode(photoIds, forKey: .photoIds)
    }
}

/// Eine Nachricht. Liegt auch im Postausgang - `gif` ist optional, damit ein
/// Auftrag aus einer aelteren Fassung weiter dekodiert.
struct MessageRequest: Codable, Hashable, Sendable {
    let id: String
    var text: String?
    var photoId: String?
    /// Ein GIF aus der Suche (Vertrag §2.7a) - nie zusammen mit `photoId`.
    var gif: GifInput?

    init(id: String = UUID().uuidString.lowercased(), text: String?, photoId: String? = nil, gif: GifInput? = nil) {
        self.id = id
        self.text = text
        self.photoId = photoId
        self.gif = gif
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(photoId, forKey: .photoId)
        try c.encode(gif, forKey: .gif)
    }
}

/// `POST /reactions` setzt die eigene Reaktion (ein neues Emoji ersetzt das
/// alte), `DELETE /reactions?target=…&reaction=…` nimmt sie zurueck (Vertrag
/// §2.7a). Auftraege im Postausgang aus der Zeit der festen Reaktionen tragen
/// noch `STARK` & Co. - die nimmt der Dienst weiter an.
struct ReactionRequest: Codable, Hashable, Sendable {
    let target: String
    let reaction: String
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
    /// Wie `MeView.typeColors` (Vertrag §5.2b) - die Kachel faerbt damit, ohne
    /// die App zu fragen. `nil` bei einem aelteren Dienst; was dann gilt, sagt
    /// `colors`.
    var typeColors: TypeColors? = nil

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
