import Foundation

/// Wann eine Mitteilung fällig ist: bei 50, 75, 90 und 100 % des Wochenlimits,
/// je Woche jede Stufe einmal (Felix, 02.11.). Springt der Wert über mehrere
/// Stufen auf einmal (Mac war zu), kommt nur die höchste - wie bei der CloudUsageBar.
struct Thresholds: Equatable, Codable, Sendable {

    static let steps = [50, 75, 90, 100]

    /// Welche Woche - der Reset-Zeitpunkt auf die Stunde gerundet. claude.ai
    /// meldet ihn bei jeder Abfrage ein paar Millisekunden anders
    /// („10:59:59.926“, „11:00:00.147“).
    var window: String?
    var sent: [Int] = []

    static func windowKey(_ resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        let hours = (resetsAt.timeIntervalSince1970 / 3_600).rounded()
        return String(Int(hours))
    }

    /// - Returns: die Stufe, für die jetzt eine Mitteilung fällig ist, und der neue
    ///   Stand zum Merken. Eine neue Woche fängt mit leerem Stand an.
    func check(percent: Double, resetsAt: Date?) -> (due: Int?, next: Thresholds) {
        let key = Self.windowKey(resetsAt)
        var next = self
        if key != window {
            next = Thresholds(window: key, sent: [])
        }
        let reached = Self.steps.filter { Double($0) <= percent }
        guard let highest = reached.last, !next.sent.contains(highest) else {
            return (nil, next)
        }
        next.sent = Array(Set(next.sent + reached)).sorted()
        return (highest, next)
    }
}
