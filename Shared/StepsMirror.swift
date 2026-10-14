import Foundation

/// Die Schritte von heute, wie Health sie zuletzt zeigte - fuer die Kacheln des
/// Sperrbildschirms (14.10.).
///
/// Eine Kachel kommt bei gesperrtem iPhone nicht an Health heran (die
/// Datenbank ist dann verschluesselt). Deshalb legt die App jeden Health-Stand
/// hier ab, und die Kachel nimmt das Groessere aus diesem Stand und dem
/// Schrittzaehler des iPhones (`StepsNow`) - Felix' Wahl: die Zahl von Health
/// samt Uhr, und trotzdem live.
///
/// Ueber die geteilte Keychain-Gruppe wie `PendingFoodMirror`: eine App-Gruppe
/// braeuchte neue Provisionierung (Entscheidung 12.10.).
enum StepsMirror {

    static let key = "steps_today"
    static let goalKey = "steps_goal"

    /// Ohne bekanntes Ziel - dieselbe Vorgabe wie der Gewicht-Tab.
    static let defaultGoal = 10_000

    struct Snapshot: Codable, Equatable, Sendable {
        let date: CalendarDate
        let steps: Int
        let updatedAt: Date
    }

    /// - Returns: ob sich etwas geaendert hat - nur dann muessen die Kacheln neu zeichnen.
    @discardableResult
    static func save(steps: Int, on date: CalendarDate = .today(), now: Date = Date()) -> Bool {
        let old = load()
        // Gleiche Zahl, gleicher Tag: nichts zu tun - auch nicht den Zeitpunkt
        // auffrischen, sonst zeichnete jede Abfrage alle Kacheln neu.
        if let old, old.date == date, old.steps == steps { return false }
        let snapshot = Snapshot(date: date, steps: steps, updatedAt: now)
        guard let data = try? APIClient.encoder().encode(snapshot),
              let text = String(data: data, encoding: .utf8) else { return false }
        Keychain.save(text, for: key)
        return true
    }

    static func load() -> Snapshot? {
        guard let text = Keychain.read(key) else { return nil }
        return try? APIClient.decoder().decode(Snapshot.self, from: Data(text.utf8))
    }

    /// Das Tagesziel aus dem Weight Tracker (`GET /api/steps/goal`).
    @discardableResult
    static func saveGoal(_ goal: Int) -> Bool {
        let text = String(goal)
        guard Keychain.read(goalKey) != text else { return false }
        Keychain.save(text, for: goalKey)
        return true
    }

    static func goal() -> Int {
        Keychain.read(goalKey).flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } ?? defaultGoal
    }
}
