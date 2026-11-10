import Foundation

/// Freunde und Serien als Text - die Begriffe aus dem Vertrag (§10.4 und §5):
/// „Tracking“, „Eiweißziel“, „Schrittziel“, „Kalorienziel“, „Serien“. Gerechnet
/// hat der Dienst; hier wird nur geschrieben. Wortgleich mit der Android-App
/// (`FriendsText.kt`), damit beide Handys dasselbe zeigen.
enum FriendsFormat {

    /// „1 Tag“, „12 Tage“ - auch „0 Tage“: eine Serie, die noch nicht begonnen
    /// hat, ist eine Zahl.
    static func days(_ count: Int) -> String {
        count == 1 ? "1 Tag" : GermanNumber.string(Double(count)) + " Tage"
    }

    /// Wie eine Serie heisst; `nil` fuer eine Art, die diese App noch nicht
    /// kennt - die Zeile fehlt dann.
    static func label(_ type: StreakType) -> String? {
        switch type {
        case .tracked: "Tracking"
        case .protein: "Eiweißziel"
        case .steps:   "Schrittziel"
        case .kcal:    "Kalorienziel"
        case .unknown: nil
        }
    }

    /// „Rekord 30“
    static func record(_ best: Int) -> String {
        "Rekord " + GermanNumber.string(Double(best))
    }

    /// Die eigene Seite ueber den Marken von heute und in der Legende der Schritte.
    static let me = "Ich"

    /// Der Anfangsbuchstabe des Freundes ueber den Marken von heute.
    static func initial(_ name: String?) -> String {
        name?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    // MARK: - Serien-Kachel im Dashboard (Vertrag §5)

    /// Die eigene Tracking-Serie: „23 Tage“; ein Strich ohne Angabe.
    static func tracking(_ tile: StreakTile?) -> String {
        tile?.tracking.map { days($0.current) } ?? "–"
    }

    /// Die laengste Freundes-Serie: „12 Tage · Person A“; `nil` ohne eine.
    static func topFriend(_ tile: StreakTile?) -> String? {
        guard let top = tile?.topFriend else { return nil }
        return [days(top.current), top.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Was gesagt wird, wenn etwas nicht ging (Vertrag §10.1)

    /// Ein Code war nicht einzuloesen.
    static func acceptError(_ error: Error) -> String {
        switch error {
        case APIError.http(404, _): "Diesen Code gibt es nicht (mehr)."
        case APIError.http(400, let message): message ?? "Das ist dein eigener Code."
        case APIError.http(409, _): "Ihr seid schon befreundet."
        case APIError.http(429, _): "Zu viele Versuche – später noch einmal."
        default: message(error)
        }
    }

    /// Hoechstens fuenf offene Codes (409).
    static func inviteError(_ error: Error) -> String {
        if case APIError.http(409, _) = error { return "Es sind schon fünf Codes offen." }
        return message(error)
    }

    /// Der zweite Stupser am selben Tag (429).
    static func nudgeError(_ error: Error) -> String {
        if case APIError.http(429, _) = error { return "Heute schon angestupst." }
        return message(error)
    }

    static func message(_ error: Error) -> String {
        if case APIError.offline = error { return "Kein Netz." }
        return error.localizedDescription
    }

    /// Was geteilt wird: der Code in der Schreibweise mit Bindestrich - so
    /// findet ihn `FriendCode.parse` auch mitten in der eingefuegten Nachricht.
    static func shareText(code: String) -> String {
        "Mein Code für Healthy: \(code)"
    }
}

/// Ein Einladungscode, wie ihn der Dienst vergibt: acht Zeichen aus
/// `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (ohne I, O, 0 und 1), als „K7Q4-M2XD“.
enum FriendCode {

    private static let alphabet = "A-HJ-NP-Z2-9"

    /// Der Code in dem, was jemand eingibt oder einfuegt. `nil`, solange keiner
    /// darin steht - dann bleibt der Knopf aus.
    ///
    /// Allein darf er gross oder klein, mit Bindestrich, Leerzeichen oder ohne
    /// stehen. Mitten in einer kopierten Nachricht nur in der Schreibweise mit
    /// Bindestrich - sonst wuerden zwei beliebige Woerter zu einem Code.
    ///
    /// - Returns: in der Schreibweise des Dienstes, „K7Q4-M2XD“
    static func parse(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let alone = "^[\(alphabet)]{4}[- ]?[\(alphabet)]{4}$"
        let within = "(?<![A-Za-z0-9-])[\(alphabet)]{4}-[\(alphabet)]{4}(?![A-Za-z0-9-])"
        let found: String
        if trimmed.range(of: alone, options: [.regularExpression, .caseInsensitive]) != nil {
            found = trimmed
        } else if let range = trimmed.range(of: within, options: [.regularExpression, .caseInsensitive]) {
            found = String(trimmed[range])
        } else {
            return nil
        }
        let plain = found.filter { $0.isLetter || $0.isNumber }.uppercased()
        return String(plain.prefix(4)) + "-" + String(plain.dropFirst(4))
    }
}

/// Der Wochenvergleich der Schritte als Balkenpaare je Tag (Vertrag §10.4) -
/// fertig ausgerechnet, die Ansicht rechnet nur noch Punkte.
struct FriendsStepsWeek: Equatable {

    /// Ein Tag der Woche. `me` und `friend` sind Hoehen als Anteil des
    /// groessten Werts der Woche; `nil` heisst: kein Wert, kein Balken.
    struct Day: Equatable, Identifiable {
        let date: CalendarDate
        /// „Mo“ … „So“.
        let label: String
        let me: Double?
        let friend: Double?

        var id: CalendarDate { date }
    }

    /// Immer Montag bis Sonntag - Tage, die noch kommen, sind leer.
    let days: [Day]
    /// Die Summen der Woche, „43.210“.
    let me: String
    let friend: String
    /// Die Summen der Vorwoche, „71.200 · 69.800“ - `nil` ohne Angabe.
    let lastWeek: String?

    /// - Returns: `nil` ohne einen einzigen Wert - dann fehlt der Vergleich
    init?(_ steps: FriendSteps?, today: CalendarDate) {
        guard let steps else { return nil }
        let values = steps.days.flatMap { [$0.me, $0.friend].compactMap { $0 } }
        guard let highest = values.max(), highest > 0 else { return nil }
        let start = steps.weekStart ?? today.adding(days: -(today.isoWeekday - 1))
        let byDate = Dictionary(steps.days.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
        days = (0..<7).map { offset in
            let date = start.adding(days: offset)
            let day = byDate[date]
            return Day(date: date, label: EnergyCardModel.weekdayLabel(date),
                       me: day?.me.map { Double($0) / Double(highest) },
                       friend: day?.friend.map { Double($0) / Double(highest) })
        }
        me = Self.total(steps.me ?? Self.sum(steps.days.map(\.me)))
        friend = Self.total(steps.friend ?? Self.sum(steps.days.map(\.friend)))
        if let last = steps.lastWeek, last.me != nil || last.friend != nil {
            lastWeek = Self.total(last.me) + " · " + Self.total(last.friend)
        } else {
            lastWeek = nil
        }
    }

    private static func sum(_ values: [Int?]) -> Int? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    private static func total(_ steps: Int?) -> String {
        steps.map { GermanNumber.string(Double($0)) } ?? "–"
    }
}
