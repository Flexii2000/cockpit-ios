#if DEBUG
import Foundation

/// Erfundene Werte fuer Aufnahmen im Simulator (`COCKPIT_DASHBOARD_DEMO=1`).
///
/// Der Simulator bekommt keine Health-Daten (`simctl` kann keine einspielen),
/// und ohne Naechte und Energie bleiben Dashboard, Recovery, Logbook und die
/// Energiezeilen leer - ansehen liessen sie sich nie. Nur im Speicher, nie
/// gespeichert, nie gesendet; Namen nur als Platzhalter („Verhalten A"), das
/// Repo ist oeffentlich. Wie `EvaluationDemo` wiederholbar: jede Aufnahme
/// zeigt dieselben Werte.
enum DashboardDemo {

    static var isOn: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_DASHBOARD_DEMO"] == "1"
    }

    /// Ein wiederholbarer Wert zwischen -1 und 1 je Tag und Zweck.
    static func noise(_ offset: Int, _ salt: UInt64) -> Double {
        var generator = EvaluationDemo.SplitMix(seed: UInt64(bitPattern: Int64(offset)) &* 0x9E3779B97F4A7C15 ^ salt)
        return Double(generator.next() % 2001) / 1000 - 1
    }

    // MARK: - Energie

    /// Die Uhr schaetzt in der Vorfuehrung 8 % zu hoch.
    static let factor = 0.92

    /// Verbrauch der Uhr `offset` Tage vor heute. Heute so, dass das Dashboard
    /// „Verbrauch ≈ 2.840 · gegessen 2.150 · Defizit ≈ 690 kcal" zeigt.
    private static func watch(_ offset: Int) -> Double {
        if offset == 0 { return 3087 }
        return (2980 + 160 * sin(Double(offset) * 0.9) + 140 * noise(offset, 1)).rounded()
    }

    private static func intake(_ offset: Int) -> Double {
        if offset == 0 { return 2150 }
        return (2150 + 320 * noise(offset, 2)).rounded()
    }

    /// Ein paar Tage sind nicht getrackt - dort gibt es kein Defizit.
    private static func tracked(_ offset: Int) -> Bool { offset % 9 != 4 }

    /// Tage zwischen `from` und `to`, nie nach heute.
    static func energyDays(from: CalendarDate, to: CalendarDate,
                           today: CalendarDate = .today()) -> [EnergyDay] {
        var days: [EnergyDay] = []
        var day = from
        while day <= min(to, today) {
            days.append(energyDay(offset: today.daysBetween(day), date: day))
            day = day.adding(days: 1)
        }
        return days
    }

    private static func energyDay(offset: Int, date: CalendarDate) -> EnergyDay {
        let watch = watch(offset)
        let expenditure = (watch * factor).rounded()
        let intake = intake(offset)
        let projected = offset == 0
        // Zentriertes Mittel ueber abgeschlossene Tage, wie beim Dienst; erst
        // vollstaendig, wenn auch der letzte Tag des Fensters vorbei ist.
        let window = (offset - 3...offset + 3).filter { $0 >= 1 }
        let average = window.isEmpty ? nil
            : window.map { (Self.watch($0) * factor).rounded() }.reduce(0, +) / Double(window.count)
        return EnergyDay(date: date, activeKcal: (watch - 2050).rounded(), basalKcal: 2050,
                         basalImputed: false, watchKcal: watch, factor: factor,
                         calibrationStatus: .ok, expenditureKcal: expenditure,
                         intakeKcal: intake, tracked: projected || tracked(offset),
                         deficitKcal: projected || tracked(offset) ? expenditure - intake : nil,
                         projected: projected, expenditureAvg7: average.map { $0.rounded() },
                         avg7Complete: offset > 3)
    }

    static func energySummary(today: CalendarDate = .today()) -> EnergySummary {
        EnergySummary(
            today: energyDay(offset: 0, date: today),
            deficit7: 460, deficit7Days: 6, expenditure7: 2610, expenditure7Days: 7,
            calibration: Calibration(status: .ok, factor: factor, rawFactor: factor,
                                     windowFrom: today.adding(days: -28), windowTo: today.adding(days: -1),
                                     measuredKcal: 2610, measuredSeKcal: 96, watchKcal: 2837,
                                     intakeKcal: 2140, weightSlopeKgPerWeek: -0.41,
                                     trackedDays: 25, weightDays: 27, watchDays: 28),
            sources: ["food": "OK"])
    }
}

private extension CalendarDate {
    /// Tage von `other` bis hierher - positiv, wenn `other` frueher liegt.
    func daysBetween(_ other: CalendarDate) -> Int {
        Calendar(identifier: .gregorian)
            .dateComponents([.day], from: other.startOfDay(), to: startOfDay()).day ?? 0
    }
}
#endif
