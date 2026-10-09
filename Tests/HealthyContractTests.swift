import XCTest
@testable import Healthy

/// Die JSON-Formen des Weight Trackers fuer Healthy, aus den Java-Records
/// unter `../weight-app/src/main/java/…/{energy,nights,recovery,logbook}/`
/// abgeschrieben - nicht aus dem Gedaechtnis. Bricht hier etwas, hat sich der
/// Vertrag geaendert (`weight-app/docs/HEALTHY-CONTRACT.md`).
final class HealthyContractTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Energie

    /// `EnergyDayView` - das Beispiel aus dem Vertrag §1.2.
    func testDecodesEnergyDay() throws {
        let day = try decode(EnergyDay.self, """
        {"date":"2026-10-08","activeKcal":512.0,"basalKcal":1834.0,"basalImputed":false,
         "watchKcal":2346.0,"factor":0.921,"calibrationStatus":"OK",
         "expenditureKcal":2161.0,"intakeKcal":1904.0,"tracked":true,"deficitKcal":257.0,
         "projected":false,"expenditureAvg7":2210.0,"avg7Complete":true}
        """)
        XCTAssertEqual(day.date, CalendarDate(year: 2026, month: 10, day: 8))
        XCTAssertEqual(day.watchKcal, 2346)
        XCTAssertEqual(day.factor, 0.921)
        XCTAssertEqual(day.calibrationStatus, .ok)
        XCTAssertEqual(day.deficitKcal, 257)
        XCTAssertEqual(day.expenditureAverage?.kcal, 2210)
        XCTAssertEqual(day.expenditureAverage?.complete, true)
    }

    /// `EnergySummary` mit `Calibration` (§1.3, §1.4); heute als Prognose.
    func testDecodesEnergySummary() throws {
        let summary = try decode(EnergySummary.self, """
        {"today":{"date":"2026-10-09","activeKcal":310.0,"basalKcal":1290.0,"basalImputed":false,
          "watchKcal":2150.0,"factor":0.921,"calibrationStatus":"CLAMPED","expenditureKcal":1980.2,
          "intakeKcal":null,"tracked":false,"deficitKcal":1980.2,"projected":true,
          "expenditureAvg7":2201.0,"avg7Complete":false},
         "deficit7":312.0,"deficit7Days":6,"expenditure7":2236.0,"expenditure7Days":7,
         "calibration":{"status":"OK","factor":0.921,"rawFactor":0.921,"windowFrom":"2026-09-11",
           "windowTo":"2026-10-08","measuredKcal":2160.0,"measuredSeKcal":96.0,"watchKcal":2346.0,
           "intakeKcal":1980.0,"weightSlopeKgPerWeek":-0.164,"trackedDays":25,"weightDays":27,"watchDays":28},
         "sources":{"food":"OK"}}
        """)
        XCTAssertEqual(summary.today?.projected, true)
        XCTAssertEqual(summary.today?.calibrationStatus, .clamped)
        XCTAssertNil(summary.today?.intakeKcal)
        XCTAssertEqual(summary.deficit7Days, 6)
        XCTAssertEqual(summary.calibration.trackedDays, 25)
        XCTAssertEqual(summary.calibration.windowFrom, CalendarDate(year: 2026, month: 9, day: 11))
        XCTAssertTrue(summary.foodAvailable)
    }

    /// Ohne Daten: kein Heute, Mittel `null`, Faktor 1 mit Grund - und ein
    /// Kalorienzaehler, der nicht antwortete.
    func testDecodesEmptyEnergySummaryAndUnknownStatus() throws {
        let summary = try decode(EnergySummary.self, """
        {"today":null,"deficit7":null,"deficit7Days":0,"expenditure7":null,"expenditure7Days":0,
         "calibration":{"status":"SOMETHING_NEW","factor":1.0,"rawFactor":null,"windowFrom":"2026-09-11",
           "windowTo":"2026-10-08","measuredKcal":null,"measuredSeKcal":null,"watchKcal":null,
           "intakeKcal":null,"weightSlopeKgPerWeek":null,"trackedDays":0,"weightDays":0,"watchDays":0},
         "sources":{"food":"UNAVAILABLE"}}
        """)
        XCTAssertNil(summary.today)
        XCTAssertNil(summary.deficit7)
        XCTAssertEqual(summary.calibration.status, .unknown, "ein neuer Status macht die Antwort nicht unlesbar")
        XCTAssertFalse(summary.foodAvailable)
    }

    // MARK: - Recovery

    /// `RecoveryDay` mit allen Bausteinen - das Beispiel aus dem Vertrag §3.1.
    func testDecodesRecoveryDay() throws {
        let day = try decode(RecoveryDay.self, """
        {"date":"2026-10-09","status":"OK","score":72,"band":"GREEN","composite":0.581,"hrvMethod":"SDNN",
         "calibration":{"nights":60,"required":14},
         "components":[{"key":"HRV","value":58.0,"unit":"ms","baseline":49.7,"z":1.12,"weight":0.5},
                       {"key":"SLEEPING_HEART_RATE","value":51.2,"unit":"bpm","baseline":54.0,"z":0.94,"weight":0.25},
                       {"key":"SLEEP","value":461.0,"unit":"min","baseline":448.0,"z":0.31,"weight":0.15},
                       {"key":"RESPIRATORY_RATE","value":14.1,"unit":"/min","baseline":14.3,"z":0.0,"weight":0.1}],
         "hrvTrend":{"mean7Ms":52.1,"nights7":6,"normalLowMs":46.9,"normalHighMs":52.6,"status":"WITHIN"}}
        """)
        XCTAssertEqual(day.status, .ok)
        XCTAssertEqual(day.score, 72)
        XCTAssertEqual(day.band, .green)
        XCTAssertEqual(day.hrvMethod, .sdnn)
        XCTAssertEqual(day.components.map(\.key), [.hrv, .sleepingHeartRate, .sleep, .respiratoryRate])
        XCTAssertEqual(day.component(.sleepingHeartRate)?.z, 0.94)
        XCTAssertEqual(day.hrvTrend?.status, .within)
        XCTAssertEqual(day.hrvTrend?.normalHighMs, 52.6)
    }

    /// Beim Kalibrieren: kein Score, die Bausteine mit Gewicht 0, kein Trend.
    func testDecodesCalibratingDay() throws {
        let day = try decode(RecoveryDay.self, """
        {"date":"2026-10-09","status":"CALIBRATING","score":null,"band":null,"composite":null,"hrvMethod":"SDNN",
         "calibration":{"nights":9,"required":14},
         "components":[{"key":"HRV","value":58.0,"unit":"ms","baseline":null,"z":null,"weight":0.0},
                       {"key":"SLEEP","value":461.0,"unit":"min","baseline":448.0,"z":0.31,"weight":0.0}],
         "hrvTrend":null}
        """)
        XCTAssertEqual(day.status, .calibrating)
        XCTAssertNil(day.score)
        XCTAssertEqual(day.calibration, RecoveryCalibration(nights: 9, required: 14))
        XCTAssertNil(day.component(.hrv)?.baseline)
        XCTAssertNil(day.hrvTrend)
    }

    /// `NO_NIGHT` aus `RecoveryCalculator.day`: leere Bausteine, alles andere
    /// `null` - und ein neuer Baustein beim Dienst macht nichts kaputt.
    func testDecodesDayWithoutNightAndUnknownValues() throws {
        let empty = try decode(RecoveryDay.self, """
        {"date":"2026-10-09","status":"NO_NIGHT","score":null,"band":null,"composite":null,"hrvMethod":null,
         "calibration":{"nights":0,"required":14},"components":[],"hrvTrend":null}
        """)
        XCTAssertEqual(empty.status, .noNight)
        XCTAssertTrue(empty.components.isEmpty)
        let novel = try decode(RecoveryDay.self, """
        {"date":"2026-10-09","status":"SOMETHING","score":null,"band":"PURPLE","composite":null,"hrvMethod":"PNN50",
         "calibration":{"nights":0,"required":14},
         "components":[{"key":"SKIN","value":1.0,"unit":"°C","baseline":null,"z":null,"weight":0.0}],"hrvTrend":null}
        """)
        XCTAssertEqual(novel.status, .unknown)
        XCTAssertEqual(novel.band, .unknown)
        XCTAssertEqual(novel.hrvMethod, .unknown)
        XCTAssertEqual(novel.components.first?.key, .unknown)
    }

    func testRecoverySettingsRoundTrip() throws {
        let settings = try decode(RecoverySettings.self, #"{"sleepNeedMinutes":480}"#)
        XCTAssertEqual(settings.sleepNeedMinutes, 480)
        let json = String(decoding: try APIClient.encoder().encode(RecoverySettings(sleepNeedMinutes: 495)),
                          as: UTF8.self)
        XCTAssertEqual(json, #"{"sleepNeedMinutes":495}"#)
    }

    // MARK: - Logbook

    /// `LogbookView` mit `Behavior` und `LogbookDay` - Platzhalter statt Namen.
    func testDecodesLogbookOverview() throws {
        let overview = try decode(LogbookOverview.self, """
        {"behaviors":[{"id":"b-1a2b3c4d","name":"Verhalten A","unit":null,"createdAt":"2026-10-01T08:00:00.123456Z","archived":false},
                      {"id":"b-5e6f7a8b","name":"Verhalten B","unit":"Stück","createdAt":"2026-10-02T08:00:00Z","archived":false},
                      {"id":"b-9c0d1e2f","name":"Verhalten C","unit":null,"createdAt":"2026-09-01T08:00:00Z","archived":true}],
         "backfillDays":14,"backfillFrom":"2026-09-25","today":"2026-10-09",
         "days":[{"date":"2026-10-08","savedAt":"2026-10-09T06:12:00Z","values":{"b-1a2b3c4d":1.0,"b-5e6f7a8b":0.0}}]}
        """)
        XCTAssertEqual(overview.backfillDays, 14)
        XCTAssertEqual(overview.active.map(\.id), ["b-1a2b3c4d", "b-5e6f7a8b"])
        XCTAssertEqual(overview.archived.first?.name, "Verhalten C")
        XCTAssertEqual(overview.behaviors[1].unit, "Stück")
        XCTAssertEqual(overview.day(CalendarDate(year: 2026, month: 10, day: 8))?.values["b-1a2b3c4d"], 1)
        XCTAssertNil(overview.day(CalendarDate(year: 2026, month: 10, day: 7)), "nie gespeichert heisst: fehlt")
    }

    /// `InsightsView` mit `PredictorView` - das Beispiel aus dem Vertrag §4.1,
    /// dazu eine Dosis- und eine Zeile ohne Effekt. `id` heisst in der App
    /// `sourceId`; eindeutig ist `key`.
    func testDecodesInsights() throws {
        let insights = try decode(LogbookInsights.self, """
        {"days":90,"from":"2026-07-11","to":"2026-10-08","nightsWithScore":71,"outcomeStatus":"OK",
         "sources":{"cohabit":"UNAVAILABLE","food":"OK"},
         "predictors":[{"key":"LOGBOOK:b-1a2b3c4d","source":"LOGBOOK","id":"b-1a2b3c4d","name":"Verhalten A",
           "kind":"BINARY","variant":"MAIN","unitLabel":null,"perUnit":1.0,
           "effect":8.12,"ciLow":3.2,"ciHigh":13.04,"p":0.0021,"pAdjusted":0.019,
           "nYes":41,"nNo":37,"n":78,"meanYes":61.3,"meanNo":52.4,"status":"OK"},
          {"key":"LOGBOOK:b-5e6f7a8b:DOSE","source":"LOGBOOK","id":"b-5e6f7a8b","name":"Verhalten B",
           "kind":"AMOUNT","variant":"DOSE","unitLabel":"Stück","perUnit":1.0,
           "effect":-1.8,"ciLow":-3.9,"ciHigh":0.3,"p":0.09,"pAdjusted":0.45,
           "nYes":null,"nNo":null,"n":23,"meanYes":null,"meanNo":null,"status":"OK"},
          {"key":"HEALTHY:active","source":"HEALTHY","id":"active","name":"Aktive Energie",
           "kind":"AMOUNT","variant":"MAIN","unitLabel":"kcal","perUnit":100.0,
           "effect":null,"ciLow":null,"ciHigh":null,"p":null,"pAdjusted":null,
           "nYes":null,"nNo":null,"n":9,"meanYes":null,"meanNo":null,"status":"TOO_FEW"}]}
        """)
        XCTAssertTrue(insights.hasEnoughNights)
        XCTAssertEqual(insights.evaluated.map(\.key), ["LOGBOOK:b-1a2b3c4d", "LOGBOOK:b-5e6f7a8b:DOSE"])
        XCTAssertEqual(insights.notEvaluated.first?.status, .tooFew)
        XCTAssertEqual(insights.strongest.count, 2)
        XCTAssertEqual(insights.predictors[1].variant, .dose)
        XCTAssertEqual(insights.predictors[1].sourceId, "b-5e6f7a8b")
        XCTAssertEqual(insights.predictors[2].perUnit, 100)
        XCTAssertEqual(insights.unavailableSources, ["coHabit"])
    }

    /// Was die App schickt: beim Aendern fehlt, was gleich bleibt; ein Tag
    /// nennt nur, was angetippt ist.
    func testLogbookRequests() throws {
        func object(_ value: some Encodable) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(value)) as? [String: Any])
        }
        XCTAssertEqual(Set(try object(BehaviorUpdateRequest(name: nil, archived: true)).keys), ["archived"])
        XCTAssertEqual(Set(try object(BehaviorUpdateRequest(name: "Verhalten Z", archived: nil)).keys), ["name"])
        XCTAssertEqual(Set(try object(NewBehaviorRequest(name: "Verhalten Z", unit: nil)).keys), ["name"])
        let day = try object(LogbookDayRequest(values: ["b-1": 1, "b-2": 2.5]))
        XCTAssertEqual(day["values"] as? [String: Double], ["b-1": 1, "b-2": 2.5])
    }

    // MARK: - Naechte

    /// `Night` wie `GET /api/nights` sie liefert (Jackson mit Bruchteilen).
    func testDecodesNight() throws {
        let nights = try decode([Night].self, """
        [{"date":"2026-10-09","sleepStart":"2026-10-08T21:34:00Z","sleepEnd":"2026-10-09T05:12:00.120Z",
          "asleepMinutes":431,"inBedMinutes":470,"awakeMinutes":24,"deepMinutes":62,"remMinutes":101,
          "coreMinutes":268,"hrvSdnnMs":48.3,"hrvSdnnSamples":4,"hrvRmssdMs":null,"hrvRmssdSamples":null,
          "sleepingHeartRate":52.4,"respiratoryRate":14.2,"source":"ios"}]
        """)
        let night = try XCTUnwrap(nights.first)
        XCTAssertEqual(night.asleepMinutes, 431)
        XCTAssertEqual(night.sleepStart, APIClient.parseInstant("2026-10-08T21:34:00Z"))
        XCTAssertNil(night.hrvRmssdMs)
        XCTAssertEqual(night.source, "ios")
    }
}
