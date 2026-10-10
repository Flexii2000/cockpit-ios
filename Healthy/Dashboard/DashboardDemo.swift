#if DEBUG
import Foundation

/// Erfundene Werte fuer Aufnahmen im Simulator (`COCKPIT_DASHBOARD_DEMO=1`).
///
/// Der Simulator bekommt keine Health-Daten (`simctl` kann keine einspielen),
/// und ohne Naechte und Energie bleiben Dashboard, Recovery, Logbook und die
/// Energie in Verlaeufen und Kacheln leer - ansehen liessen sie sich nie. Nur
/// im Speicher, nie gespeichert, nie gesendet; Namen nur als Platzhalter
/// („Verhalten A"), das Repo ist oeffentlich. Wie `EvaluationDemo`
/// wiederholbar: jede Aufnahme zeigt dieselben Werte.
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
    /// „Defizit ≈ 690 kcal" aus „gegessen 2.150" und „Verbrauch ≈ 2.840" zeigt.
    private static func watch(_ offset: Int) -> Double {
        if offset == 0 { return 3087 }
        return (2980 + 160 * sin(Double(offset) * 0.9) + 140 * noise(offset, 1)).rounded()
    }

    /// Der kalibrierte Verbrauch, wie ihn der Dienst rechnet.
    private static func expenditure(_ offset: Int) -> Double {
        (watch(offset) * factor).rounded()
    }

    /// Gegessen laut Kalorienzaehler. Vorgestern ein Ueberschuss-Tag und vor
    /// sechs Tagen ein fast ausgeglichener (die Woche der Energie-Karte zeigt
    /// beides: Balken nach unten, duenner Strich), vor gut drei Wochen eine
    /// Woche drueber (der Verlauf zeigt eine Ueberschuss-Stelle). An nicht
    /// getrackten Tagen fehlt etwas - wie im Leben, wenn das Abendessen nicht
    /// eingetragen ist; die Flaeche ist dort breiter, als die Linie „Defizit
    /// ⌀" hoch ist (Vertrag §5).
    private static func intake(_ offset: Int) -> Double {
        if offset == 0 { return 2150 }
        if !tracked(offset) { return (1600 + 150 * noise(offset, 8)).rounded() }
        if offset == 2 { return 3160 }
        if offset == 6 { return expenditure(6) - 15 }
        if (16...22).contains(offset) { return (3250 + 180 * noise(offset, 9)).rounded() }
        return (2150 + 320 * noise(offset, 2)).rounded()
    }

    /// Ein paar Tage sind nicht getrackt - dort gibt es kein Defizit. Vor vier
    /// Tagen einer, damit die Woche der Karte einen Tag ohne Wert hat.
    private static func tracked(_ offset: Int) -> Bool { offset % 11 != 4 }

    /// Verbrauch minus gegessen - wie beim Dienst nur an getrackten Tagen und
    /// heute.
    private static func deficit(_ offset: Int) -> Double? {
        offset == 0 || tracked(offset) ? expenditure(offset) - intake(offset) : nil
    }

    /// Mittel ueber D−3 … D+3, nur abgeschlossene Tage mit Wert - heute zaehlt
    /// nie mit (`centeredAverage` beim Dienst).
    private static func centered(_ offset: Int, _ value: (Int) -> Double?) -> Double? {
        let values = (offset - 3...offset + 3).filter { $0 >= 1 }.compactMap(value)
        return values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count)).rounded()
    }

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
        let projected = offset == 0
        let average = centered(offset) { expenditure($0) }
        // Beide Mittel erst vollstaendig, wenn auch der letzte Tag des
        // Fensters vorbei ist - wie beim Dienst.
        return EnergyDay(date: date, activeKcal: (watch - 2050).rounded(), basalKcal: 2050,
                         basalImputed: false, watchKcal: watch, factor: factor,
                         calibrationStatus: .ok, expenditureKcal: expenditure(offset),
                         intakeKcal: intake(offset), tracked: projected || tracked(offset),
                         deficitKcal: deficit(offset), projected: projected,
                         expenditureAvg7: average, deficitAvg7: centered(offset, deficit),
                         avg7Complete: average != nil && offset > 3)
    }

    /// Die Kacheln und die Karte: die sieben vollen Tage bis gestern, wie
    /// beim Dienst - so passen „⌀ 7 T" und die Woche zusammen.
    static func energySummary(today: CalendarDate = .today()) -> EnergySummary {
        let deficits = (1...7).compactMap(deficit)
        let expenditures = (1...7).map(expenditure)
        return EnergySummary(
            today: energyDay(offset: 0, date: today),
            deficit7: deficits.isEmpty ? nil : (deficits.reduce(0, +) / Double(deficits.count)).rounded(),
            deficit7Days: deficits.count,
            expenditure7: (expenditures.reduce(0, +) / Double(expenditures.count)).rounded(),
            expenditure7Days: expenditures.count,
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

    /// Das kcal-Ziel der Vorfuehrung.
    static let kcalTarget: Double = 2300

    /// Ein Tag des Essen-Tabs: gegessen wie in der Energie (heute 2.150),
    /// aber ohne Eintraege - Gerichte waeren Namen, und mit einer kurzen Liste
    /// kommt der Verlauf schneller ins Bild. Kuenftige Tage sind leer.
    static func foodDay(_ date: CalendarDate = .today(), today: CalendarDate = .today()) -> DaySummary {
        let offset = today.daysBetween(date)
        let kcal = offset >= 0 ? intake(offset) : 0
        // Eiweiss, Kohlenhydrate und Fett im Verhaeltnis des freigegebenen
        // Tages (150 / 220 / 64 g bei 2.150 kcal).
        let protein = (150 * kcal / 2150).rounded(), carbs = (220 * kcal / 2150).rounded()
        let fat = (64 * kcal / 2150).rounded()
        let json = """
        {"date":"\(date.iso)",
         "targets":{"kcal":\(kcalTarget),"proteinG":180,"carbsG":240,"fatG":70},
         "consumed":{"kcal":\(kcal),"proteinG":\(protein),"carbsG":\(carbs),"fatG":\(fat)},
         "remaining":{"kcal":\(kcalTarget - kcal),"proteinG":\(180 - protein),"carbsG":\(240 - carbs),
                      "fatG":\(70 - fat)},
         "entries":[],"mealTargets":{}}
        """
        return try! APIClient.decoder().decode(DaySummary.self, from: Data(json.utf8))
    }

    /// Die Tagessummen des Kalorienzaehlers - jeder Tag bis heute hat etwas,
    /// die nicht getrackten nur einen Teil.
    static func foodTotals(from: CalendarDate, to: CalendarDate,
                           today: CalendarDate = .today()) -> [DayTotal] {
        days(from: from, to: to, today: today).map { offset, date in
            DayTotal(date: date, consumed: Nutrients(kcal: intake(offset), proteinG: 0, carbsG: 0, fatG: 0))
        }
    }

    /// „kcal ⌀" wie im Kalorienzaehler (`dailyAverages`): zentriert ueber die
    /// abgeschlossenen Tage mit Eintrag - die halb erfassten zaehlen mit, und
    /// genau deshalb ist die Flaeche dort breiter, als die Linie „Defizit ⌀"
    /// hoch ist.
    static func foodAverages(from: CalendarDate, to: CalendarDate,
                             today: CalendarDate = .today()) -> [DayAverage] {
        days(from: from, to: to, today: today).compactMap { offset, date in
            let window = (offset - 3...offset + 3).filter { $0 >= 1 }
            guard !window.isEmpty else { return nil }
            let kcal = window.map(intake).reduce(0, +) / Double(window.count)
            return DayAverage(date: date, kcal: kcal.rounded(), days: window.count, complete: offset > 3)
        }
    }

    /// Die Tage zwischen `from` und `to` bis heute, mit ihrem Abstand zu heute.
    private static func days(from: CalendarDate, to: CalendarDate,
                             today: CalendarDate) -> [(offset: Int, date: CalendarDate)] {
        var result: [(offset: Int, date: CalendarDate)] = []
        var day = from
        while day <= min(to, today) {
            result.append((today.daysBetween(day), day))
            day = day.adding(days: 1)
        }
        return result
    }

    /// Das Gewicht `offset` Tage vor heute: langsam fallend, mit Rauschen;
    /// heute genau der Wert der Karte.
    private static func weight(_ offset: Int) -> Double {
        if offset == 0 { return 82.6 }
        return ((82.6 + 0.018 * Double(offset) + 0.35 * noise(offset, 21)) * 10).rounded() / 10
    }

    /// An manchen Tagen wird nicht gewogen.
    private static func weighed(_ offset: Int) -> Bool { offset % 5 != 3 }

    /// Die Kurve des Gewicht-Tabs fuer einen Zeitraum - dieselbe Form wie beim
    /// Dienst: das Fenster bis heute und ein paar Tage Vorgriff fuer die
    /// Zielkurve, die Mittel zentriert und am offenen Rand unvollstaendig.
    static func weightPoints(_ range: WeightRange, today: CalendarDate = .today()) -> [WeightPoint] {
        let recordingStart = CalendarDate(year: 2025, month: 1, day: 5)
        let (back, ahead): (Int, Int) = switch range {
        case .month:   (29, 3)
        case .last90:  (89, 7)
        case .last180: (179, 7)
        case .year:    (364, 7)
        case .threeYears, .allTime: (today.daysBetween(recordingStart), 7)
        }
        return (-ahead...back).reversed().map { offset in
            func mean(_ half: Int) -> Double? {
                let values = (offset - half...offset + half).filter { $0 >= 0 && weighed($0) }.map(weight)
                return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            return WeightPoint(date: today.adding(days: -offset),
                               measured: offset >= 0 && weighed(offset) ? weight(offset) : nil,
                               avg7: mean(3), avg14: mean(7), avg30: mean(15),
                               avg7Complete: offset >= 3, avg14Complete: offset >= 7,
                               avg30Complete: offset >= 15,
                               // Knapp ueber dem Gewicht - das Residuum der Karte ist −0,3.
                               target: 83.2 + 0.018 * Double(offset))
        }
    }

    static let steps = 8123

    // MARK: - Logbook

    /// Platzhalter - echte Verhaltensweisen gehoeren nicht ins Repo und nicht
    /// in Bilder.
    static let behaviors = [
        Behavior(id: "b-demo-a", name: "Verhalten A", unit: nil, createdAt: nil, archived: false),
        Behavior(id: "b-demo-b", name: "Verhalten B", unit: nil, createdAt: nil, archived: false),
        Behavior(id: "b-demo-c", name: "Verhalten C", unit: "Stück", createdAt: nil, archived: false),
        Behavior(id: "b-demo-d", name: "Verhalten D", unit: nil, createdAt: nil, archived: false),
        Behavior(id: "b-demo-e", name: "Verhalten E", unit: nil, createdAt: nil, archived: true),
    ]

    /// Die Nachtragsfrist mit ein paar Luecken - gestern ist offen, damit die
    /// Karte „gestern offen" zeigt.
    static func logbookOverview(today: CalendarDate = .today()) -> LogbookOverview {
        let days = (2...14).filter { $0 != 6 && $0 != 9 }.map { offset in
            LogbookDay(date: today.adding(days: -offset), savedAt: nil, values: [
                "b-demo-a": noise(offset, 11) > 0 ? 1 : 0,
                "b-demo-b": noise(offset, 12) > 0.4 ? 1 : 0,
                "b-demo-c": noise(offset, 13) > 0 ? (2 + 2 * noise(offset, 14)).rounded() : 0,
                "b-demo-d": offset % 3 == 0 ? 1 : 0,
            ])
        }
        return LogbookOverview(behaviors: behaviors, backfillDays: 14, backfillFrom: today.adding(days: -14),
                               today: today, days: days)
    }

    /// Effekte wie aus dem Dienst, sortiert wie dort: signifikant zuerst, dann
    /// nach Groesse, dann die nicht auswertbaren.
    static func logbookInsights(days: Int, today: CalendarDate = .today()) -> LogbookInsights {
        func row(_ key: String, _ source: PredictorSource, _ name: String, _ kind: PredictorKind,
                 _ variant: PredictorVariant = .main, unit: String? = nil, perUnit: Double = 1,
                 effect: Double? = nil, ci: (Double, Double)? = nil, p: Double? = nil, pAdjusted: Double? = nil,
                 yes: Int? = nil, no: Int? = nil, n: Int, status: PredictorStatus = .ok) -> Predictor {
            Predictor(key: key, source: source, sourceId: key, name: name, kind: kind, variant: variant,
                      unitLabel: unit, perUnit: perUnit, effect: effect, ciLow: ci?.0, ciHigh: ci?.1, p: p,
                      pAdjusted: pAdjusted, nYes: yes, nNo: no, n: n, meanYes: nil, meanNo: nil, status: status)
        }
        // Kuerzere Zeitraeume haben weniger Tage - und breitere Intervalle.
        let scale = Double(min(days, 90)) / 90
        let predictors = [
            row("LOGBOOK:b-demo-a", .logbook, "Verhalten A", .binary, effect: 8.12, ci: (3.2, 13.04),
                p: 0.0004, pAdjusted: 0.004, yes: Int(41 * scale), no: Int(37 * scale), n: Int(78 * scale)),
            row("COHABIT:c-demo", .cohabit, "Gewohnheit A", .binary, effect: -6.4, ci: (-10.9, -1.9),
                p: 0.003, pAdjusted: 0.03, yes: Int(30 * scale), no: Int(52 * scale), n: Int(82 * scale)),
            row("HEALTHY:steps", .healthy, "Schritte", .amount, unit: "Schritte", perUnit: 1000,
                effect: 1.3, ci: (0.2, 2.4), p: 0.02, pAdjusted: 0.12, n: Int(84 * scale)),
            row("LOGBOOK:b-demo-c", .logbook, "Verhalten C", .binary, effect: -3.0, ci: (-7.5, 1.5),
                p: 0.19, pAdjusted: 0.76, yes: Int(44 * scale), no: Int(34 * scale), n: Int(78 * scale)),
            row("LOGBOOK:b-demo-c:DOSE", .logbook, "Verhalten C", .amount, .dose, unit: "Stück",
                effect: -1.8, ci: (-3.9, 0.3), p: 0.09, pAdjusted: 0.45, n: Int(44 * scale)),
            row("HEALTHY:deficit", .healthy, "Defizit", .amount, unit: "kcal", perUnit: 100,
                effect: -0.4, ci: (-1.1, 0.3), p: 0.26, pAdjusted: 0.78, n: Int(70 * scale)),
            row("LOGBOOK:b-demo-b", .logbook, "Verhalten B", .binary, yes: 3, no: 5, n: 8, status: .tooFew),
            row("LOGBOOK:b-demo-d", .logbook, "Verhalten D", .binary, yes: 12, no: 2, n: 14, status: .tooFew),
            row("HEALTHY:active", .healthy, "Aktive Energie", .amount, unit: "kcal", perUnit: 100, n: 9,
                status: .tooFew),
        ]
        return LogbookInsights(days: days, from: today.adding(days: -days), to: today.adding(days: -1),
                               nightsWithScore: Int(71 * scale), outcomeStatus: "OK",
                               sources: ["cohabit": "OK", "food": "OK"], predictors: predictors)
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
