import Foundation

/// Ein Tag, auf eine Kachel eingedampft.
///
/// Liegt neben der View und nicht darin - wie `WeightChartData` und
/// `FoodChartData`, und aus demselben Grund: in einer View waere die einzige
/// Stelle mit echter Logik nicht zu pruefen.
struct RemainingCalories: Codable, Equatable, Sendable {

    let date: CalendarDate
    let consumed: Nutrients
    let targets: Nutrients
    /// Der Rest kommt vom Server, statt hier neu ausgerechnet zu werden -
    /// sonst gaebe es zwei Rechenwege fuer dieselbe Zahl.
    let remaining: Nutrients
    let fetchedAt: Date

    init(day: DaySummary, fetchedAt: Date = Date()) {
        self.date = day.date
        self.consumed = day.consumed
        self.targets = day.targets
        self.remaining = day.remaining
        self.fetchedAt = fetchedAt
    }

    var isOver: Bool { remaining.kcal < 0 }

    /// Wie im Essen-Tab: der Bogen reicht bis zum 1,25-fachen des Ziels, damit
    /// die Zielkerbe nicht am Bogenende sitzt.
    var ratio: Double {
        targets.kcal > 0 ? consumed.kcal / (targets.kcal * 1.25) : 0
    }

    /// Gehoert dieser Stand ueberhaupt noch zu heute?
    ///
    /// Wenn nicht, darf die Zahl nicht als heutiger Rest auftreten. Um
    /// Mitternacht springt „uebrig" auf das volle Tagesziel zurueck - ein Rest
    /// von gestern ist deshalb keine alte Wahrheit, sondern eine falsche
    /// Aussage.
    func isStale(today: CalendarDate = .today()) -> Bool { date != today }

    /// Wann die Kachel das naechste Mal rechnen soll.
    ///
    /// Halbstuendlich faengt Eintraege ein, die im Browser gemacht wurden -
    /// die erreichen die App nie. Der Mitternachtstermin sorgt dafuer, dass
    /// zum Tageswechsel neu gerechnet wird, statt den Rest von gestern
    /// stehenzulassen. Beides ist eine **Bitte** an WidgetKit, keine Zusage:
    /// wird das Budget knapp, dehnt das System die Abstaende stillschweigend.
    static func nextRefresh(after now: Date, in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let halbeStunde = now.addingTimeInterval(30 * 60)
        guard let morgen = calendar.date(byAdding: .day, value: 1, to: now),
              let mitternacht = calendar.dateInterval(of: .day, for: morgen)?.start
        else { return halbeStunde }
        return min(halbeStunde, mitternacht.addingTimeInterval(60))
    }
}
