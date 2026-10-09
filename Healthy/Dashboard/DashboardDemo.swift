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

extension DashboardDemo {

    // MARK: - Recovery

    /// Die Recovery `offset` Tage vor heute. Heute so wie das freigegebene
    /// Dashboard („HRV 58 ms · RHF 49 · 7:41 h", 72 % gruen); davor ein paar
    /// Wochen mit Luecken, Naechten ohne HRV und einem Normalband, das sich
    /// langsam bewegt.
    static func recoveryDay(offset: Int, today: CalendarDate = .today()) -> RecoveryDay? {
        let date = today.adding(days: -offset)
        if offset == 0 {
            return RecoveryDay(
                date: date, status: .ok, score: 72, band: .green, composite: 0.581, hrvMethod: .sdnn,
                calibration: RecoveryCalibration(nights: 60, required: 14),
                components: [
                    RecoveryComponent(key: .hrv, value: 58, unit: "ms", baseline: 49.7, z: 1.12, weight: 0.5),
                    RecoveryComponent(key: .sleepingHeartRate, value: 49.2, unit: "bpm", baseline: 52.0,
                                      z: 1.85, weight: 0.25),
                    RecoveryComponent(key: .sleep, value: 461, unit: "min", baseline: 448, z: 0.31, weight: 0.15),
                    RecoveryComponent(key: .respiratoryRate, value: 14.6, unit: "/min", baseline: 14.3,
                                      z: -0.9, weight: 0.1),
                ],
                hrvTrend: HrvTrend(mean7Ms: 52.1, nights7: 6, normalLowMs: 46.9, normalHighMs: 52.6,
                                   status: .within))
        }
        // Die Uhr am Ladekabel: keine Nacht.
        if offset % 11 == 6 { return nil }
        let low = (46 + 1.2 * sin(Double(offset) * 0.08)) * 10
        let band = (low.rounded() / 10, (low + 58).rounded() / 10)
        let heart = 52 + 2.5 * noise(offset, 5)
        let sleep = (440 + 45 * noise(offset, 6)).rounded()
        let breath = 14.3 + 0.4 * noise(offset, 7)
        let heartComponent = RecoveryComponent(key: .sleepingHeartRate, value: (heart * 10).rounded() / 10,
                                               unit: "bpm", baseline: 52, z: -(heart - 52) / 1.5, weight: 0.25)
        let sleepComponent = RecoveryComponent(key: .sleep, value: sleep, unit: "min", baseline: 448,
                                               z: (sleep - 448) / 30, weight: 0.15)
        let breathComponent = RecoveryComponent(key: .respiratoryRate, value: (breath * 10).rounded() / 10,
                                                unit: "/min", baseline: 14.3, z: -max(0, (breath - 14.3) / 0.3),
                                                weight: 0.1)
        // Ab und zu misst die Uhr nachts keine HRV - die Werte stehen trotzdem da.
        if offset % 17 == 9 {
            return RecoveryDay(date: date, status: .noHrv, score: nil, band: nil, composite: nil, hrvMethod: nil,
                               calibration: RecoveryCalibration(nights: 60, required: 14),
                               components: [heartComponent, sleepComponent, breathComponent], hrvTrend: nil)
        }
        let hrv = (49.5 + 5 * sin(Double(offset) * 0.7) + 4 * noise(offset, 3)).rounded()
        let middle = (band.0 + band.1) / 2
        let score = Int(max(4, min(96, 50 + (hrv - middle) * 5 + 8 * noise(offset, 4))).rounded())
        return RecoveryDay(
            date: date, status: .ok, score: score,
            band: score >= 67 ? .green : score <= 33 ? .red : .yellow, composite: nil, hrvMethod: .sdnn,
            calibration: RecoveryCalibration(nights: 60, required: 14),
            components: [RecoveryComponent(key: .hrv, value: hrv, unit: "ms", baseline: middle,
                                           z: (log(hrv) - log(middle)) / 0.12, weight: 0.5),
                         heartComponent, sleepComponent, breathComponent],
            hrvTrend: HrvTrend(mean7Ms: nil, nights7: 0, normalLowMs: band.0, normalHighMs: band.1,
                               status: .unknown))
    }

    /// Die Tage mit einer Nacht zwischen `from` und `to`, wie `GET /api/recovery`.
    static func recoveryDays(from: CalendarDate, to: CalendarDate,
                             today: CalendarDate = .today()) -> [RecoveryDay] {
        var days: [RecoveryDay] = []
        var day = from
        while day <= min(to, today) {
            if let recovery = recoveryDay(offset: today.daysBetween(day), today: today) {
                days.append(recovery)
            }
            day = day.adding(days: 1)
        }
        return days
    }

    // MARK: - Gewicht und Essen

    /// Ein erfundenes Gewicht - nicht Felix' echtes, das Bild landet in Doku
    /// und Berichten.
    static func weightSummary(today: CalendarDate = .today()) -> WeightSummary {
        let json = """
        {"date":"\(today.iso)","current":82.6,"avg7":82.9,"avg14":83.1,"avg30":83.6,"target":83.2,
         "targetDate":"2026-12-20","goalWeight":80.0,"startWeight":92.0,"recordingStart":"2025-01-05",
         "corridorLower":null,"corridorUpper":null,"corridorReachedOn":null,
         "residual7":-0.3,"residual7Days":7}
        """
        // Fest im Code und vom selben Decoder gelesen wie die echte Antwort.
        return try! APIClient.decoder().decode(WeightSummary.self, from: Data(json.utf8))
    }

    static func foodDay(today: CalendarDate = .today()) -> DaySummary {
        let json = """
        {"date":"\(today.iso)",
         "targets":{"kcal":2300,"proteinG":180,"carbsG":240,"fatG":70},
         "consumed":{"kcal":2150,"proteinG":150,"carbsG":220,"fatG":64},
         "remaining":{"kcal":150,"proteinG":30,"carbsG":20,"fatG":6},
         "entries":[],"mealTargets":{}}
        """
        return try! APIClient.decoder().decode(DaySummary.self, from: Data(json.utf8))
    }

    static let steps = 8123
}

private extension CalendarDate {
    /// Tage von `other` bis hierher - positiv, wenn `other` frueher liegt.
    func daysBetween(_ other: CalendarDate) -> Int {
        Calendar(identifier: .gregorian)
            .dateComponents([.day], from: other.startOfDay(), to: startOfDay()).day ?? 0
    }
}
#endif
