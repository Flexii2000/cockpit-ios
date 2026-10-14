import CoreMotion
import Foundation

/// Was die Schritte-Kacheln zeigen.
struct StepsReading: Equatable, Sendable {
    /// `nil`: weder Health noch der Schrittzaehler wissen etwas ueber heute.
    let steps: Int?
    let goal: Int

    var ratio: Double { goal > 0 ? min(Double(steps ?? 0) / Double(goal), 1) : 0 }
}

/// Die Schritte von heute fuer den Sperrbildschirm: das Groessere aus dem
/// letzten Health-Stand der App (`StepsMirror`, samt Uhr) und dem
/// Schrittzaehler des iPhones (live, auch gesperrt) - Felix' Wahl vom 14.10.
///
/// Warum das Groessere: Health fuehrt iPhone und Uhr zusammen und liegt deshalb
/// fast immer darueber - nur ist der Stand der App so alt wie ihr letzter Blick
/// auf Health. Der Schrittzaehler zaehlt nur, was das iPhone selbst gemerkt hat,
/// dafuer jetzt. Das Maximum ist nie kleiner als eine der beiden Wahrheiten.
enum StepsNow {

    /// Rein, damit es sich ohne Geraet pruefen laesst.
    static func combine(mirror: StepsMirror.Snapshot?, pedometer: Int?, goal: Int,
                        today: CalendarDate) -> StepsReading {
        let health = mirror.flatMap { $0.date == today ? $0.steps : nil }
        let steps: Int? = switch (health, pedometer) {
        case let (h?, p?): max(h, p)
        case let (h?, nil): h
        case let (nil, p?): p
        case (nil, nil): nil
        }
        return StepsReading(steps: steps, goal: goal)
    }

    static func read(now: Date = Date()) async -> StepsReading {
        let today = CalendarDate(date: now)
        return combine(mirror: StepsMirror.load(), pedometer: await pedometerSteps(since: today.startOfDay(), until: now),
                       goal: StepsMirror.goal(), today: today)
    }

    /// Die Schritte des iPhones seit Mitternacht - `nil` ohne Erlaubnis oder
    /// ohne Schrittzaehler. Die Erlaubnis holt die App (`requestPermission`);
    /// eine Kachel kann nicht fragen.
    static func pedometerSteps(since start: Date, until end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .authorized else { return nil }
        return await query(since: start, until: end)
    }

    /// Fragt einmal nach „Bewegung & Fitness“ - nur aus der App, im Vordergrund:
    /// die erste Abfrage ist es, die iOS fragen laesst.
    static func requestPermission() async {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .notDetermined else { return }
        let now = Date()
        _ = await query(since: now.addingTimeInterval(-60), until: now)
    }

    private static func query(since start: Date, until end: Date) async -> Int? {
        let pedometer = CMPedometer()
        let steps: Int? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
        // Bis hierher lebt der Zaehler - gibt man ihn vorher frei, kommt die Antwort nie.
        withExtendedLifetime(pedometer) {}
        return steps
    }

    /// Wann die Schritte-Kacheln neu zeichnen sollen: alle 20 Minuten - der
    /// Schrittzaehler laeuft weiter, auch wenn niemand die App oeffnet - und
    /// gleich nach Mitternacht. Eine Bitte an WidgetKit, keine Zusage.
    static func nextRefresh(after now: Date, in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let soon = now.addingTimeInterval(20 * 60)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let midnight = calendar.dateInterval(of: .day, for: tomorrow)?.start
        else { return soon }
        return min(soon, midnight.addingTimeInterval(60))
    }
}
