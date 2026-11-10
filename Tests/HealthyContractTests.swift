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

    /// `EnergyDayView` - das Beispiel aus dem Vertrag §1.2, samt `deficitAvg7`.
    func testDecodesEnergyDay() throws {
        let day = try decode(EnergyDay.self, """
        {"date":"2026-10-08","activeKcal":512.0,"basalKcal":1834.0,"basalImputed":false,
         "watchKcal":2346.0,"factor":0.921,"calibrationStatus":"OK",
         "expenditureKcal":2161.0,"intakeKcal":1904.0,"tracked":true,"deficitKcal":257.0,
         "projected":false,"expenditureAvg7":2210.0,"deficitAvg7":318.0,"avg7Complete":true}
        """)
        XCTAssertEqual(day.date, CalendarDate(year: 2026, month: 10, day: 8))
        XCTAssertEqual(day.watchKcal, 2346)
        XCTAssertEqual(day.factor, 0.921)
        XCTAssertEqual(day.calibrationStatus, .ok)
        XCTAssertEqual(day.deficitKcal, 257)
        XCTAssertEqual(day.expenditureAverage?.kcal, 2210)
        XCTAssertEqual(day.expenditureAverage?.complete, true)
        XCTAssertEqual(day.deficitAvg7, 318)
        XCTAssertEqual(day.deficitAverage?.kcal, 318)
        XCTAssertEqual(day.deficitAverage?.complete, true, "avg7Complete gilt fuer beide Mittel")
    }

    /// Ein Weight Tracker von vor dem Feld schickt kein `deficitAvg7` - der Tag
    /// bleibt lesbar, nur die Kurve fehlt. `null` (kein getrackter Tag im
    /// Fenster) heisst dasselbe, und ein Ueberschuss ist negativ.
    func testDeficitAverageIsOptionalAndSigned() throws {
        let older = try decode(EnergyDay.self, """
        {"date":"2026-10-08","activeKcal":512.0,"basalKcal":1834.0,"basalImputed":false,
         "watchKcal":2346.0,"factor":0.921,"calibrationStatus":"OK",
         "expenditureKcal":2161.0,"intakeKcal":1904.0,"tracked":true,"deficitKcal":257.0,
         "projected":false,"expenditureAvg7":2210.0,"avg7Complete":true}
        """)
        XCTAssertNil(older.deficitAvg7)
        XCTAssertNil(older.deficitAverage)

        let untracked = try decode(EnergyDay.self, """
        {"date":"2026-10-07","activeKcal":400.0,"basalKcal":1830.0,"basalImputed":false,
         "watchKcal":2230.0,"factor":0.921,"calibrationStatus":"OK","expenditureKcal":2054.0,
         "intakeKcal":null,"tracked":false,"deficitKcal":null,"projected":false,
         "expenditureAvg7":2190.0,"deficitAvg7":null,"avg7Complete":false}
        """)
        XCTAssertNil(untracked.deficitAverage)
        XCTAssertEqual(untracked.expenditureAverage?.complete, false)

        let surplus = try decode(EnergyDay.self, """
        {"date":"2026-10-06","activeKcal":420.0,"basalKcal":1830.0,"basalImputed":false,
         "watchKcal":2250.0,"factor":0.921,"calibrationStatus":"OK","expenditureKcal":2072.0,
         "intakeKcal":2500.0,"tracked":true,"deficitKcal":-428.0,"projected":false,
         "expenditureAvg7":2180.0,"deficitAvg7":-120.0,"avg7Complete":false}
        """)
        XCTAssertEqual(surplus.deficitAverage?.kcal, -120)
        XCTAssertEqual(surplus.deficitAverage?.complete, false, "gestrichelt wie „Verbrauch ⌀\"")
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

    /// `RecoveryDay` mit allen Bausteinen - das Beispiel aus dem Vertrag §3.1
    /// (seit 22.10.: Schlaf mit Gewicht 0, dazu die Handgelenktemperatur).
    func testDecodesRecoveryDay() throws {
        let day = try decode(RecoveryDay.self, """
        {"date":"2026-10-09","status":"OK","score":67,"band":"GREEN","composite":0.831,"hrvMethod":"SDNN",
         "calibration":{"nights":30,"required":14},
         "components":[{"key":"HRV","value":58.0,"unit":"ms","baseline":49.7,"z":1.12,"weight":0.55},
                       {"key":"SLEEPING_HEART_RATE","value":51.2,"unit":"bpm","baseline":54.0,"z":0.94,"weight":0.25},
                       {"key":"SLEEP","value":461.0,"unit":"min","baseline":448.0,"z":0.31,"weight":0.0},
                       {"key":"RESPIRATORY_RATE","value":14.1,"unit":"/min","baseline":14.3,"z":0.0,"weight":0.1},
                       {"key":"WRIST_TEMPERATURE","value":35.84,"unit":"°C","baseline":35.8,"z":-0.2,"weight":0.1}],
         "hrvTrend":{"mean7Ms":52.1,"nights7":6,"normalLowMs":46.9,"normalHighMs":52.6,"status":"WITHIN"}}
        """)
        XCTAssertEqual(day.status, .ok)
        XCTAssertEqual(day.score, 67)
        XCTAssertEqual(day.band, .green)
        XCTAssertEqual(day.hrvMethod, .sdnn)
        XCTAssertEqual(day.calibration, RecoveryCalibration(nights: 30, required: 14))
        XCTAssertEqual(day.components.map(\.key),
                       [.hrv, .sleepingHeartRate, .sleep, .respiratoryRate, .wristTemperature])
        XCTAssertEqual(day.component(.sleepingHeartRate)?.z, 0.94)
        XCTAssertEqual(day.component(.wristTemperature)?.value, 35.84)
        XCTAssertEqual(day.component(.wristTemperature)?.unit, "°C")
        XCTAssertEqual(day.component(.wristTemperature)?.z, -0.2)
        XCTAssertEqual(day.component(.sleep)?.counts, false, "Schlaf geht nicht ein")
        XCTAssertEqual(day.component(.hrv)?.counts, true)
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

    /// `LogbookView` (Dienst) mit `Behavior` und `LogbookDay` - Platzhalter statt Namen.
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
           "hrvEffectPercent":9.4,"sleepingHeartRateEffectBpm":-1.85,
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
        XCTAssertEqual(insights.predictors[0].hrvEffectPercent, 9.4)
        XCTAssertEqual(insights.predictors[0].sleepingHeartRateEffectBpm, -1.85)
        XCTAssertNil(insights.predictors[1].hrvEffectPercent, "ein aelterer Dienst kennt die Felder nicht")
        XCTAssertNil(insights.predictors[1].sleepingHeartRateEffectBpm)
    }

    /// Was die App schickt: beim Aendern fehlt, was gleich bleibt; ein Wert je
    /// Tipp, und zum Leeren ausdruecklich `null` (Vertrag §4).
    func testLogbookRequests() throws {
        func object(_ value: some Encodable) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(value)) as? [String: Any])
        }
        XCTAssertEqual(Set(try object(BehaviorUpdateRequest(name: nil, archived: true)).keys), ["archived"])
        XCTAssertEqual(Set(try object(BehaviorUpdateRequest(name: "Verhalten Z", archived: nil)).keys), ["name"])
        XCTAssertEqual(Set(try object(NewBehaviorRequest(name: "Verhalten Z", unit: nil)).keys), ["name"])
        let set = LogbookChange.setValue(date: CalendarDate(year: 2026, month: 10, day: 11), behaviorId: "b-2",
                                         value: 2.5).request
        XCTAssertEqual(set.method, "PUT")
        XCTAssertEqual(set.path, "/api/logbook/days/2026-10-11/values/b-2")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(set.body)) as? [String: Any])
        XCTAssertEqual(body["value"] as? Double, 2.5)
        let clear = LogbookChange.setValue(date: CalendarDate(year: 2026, month: 10, day: 11), behaviorId: "b-2",
                                           value: nil).request
        XCTAssertEqual(String(decoding: try XCTUnwrap(clear.body), as: UTF8.self), #"{"value":null}"#)
    }

    // MARK: - Naechte

    /// `Night` wie `GET /api/nights` sie liefert (Jackson mit Bruchteilen).
    func testDecodesNight() throws {
        let nights = try decode([Night].self, """
        [{"date":"2026-10-09","sleepStart":"2026-10-08T21:34:00Z","sleepEnd":"2026-10-09T05:12:00.120Z",
          "asleepMinutes":431,"inBedMinutes":470,"awakeMinutes":24,"deepMinutes":62,"remMinutes":101,
          "coreMinutes":268,"hrvSdnnMs":48.3,"hrvSdnnSamples":4,"hrvRmssdMs":null,"hrvRmssdSamples":null,
          "sleepingHeartRate":52.4,"respiratoryRate":14.2,"wristTemperatureCelsius":35.84,"source":"ios"},
         {"date":"2026-10-10","asleepMinutes":402,"source":"ios"}]
        """)
        let night = try XCTUnwrap(nights.first)
        XCTAssertEqual(night.asleepMinutes, 431)
        XCTAssertEqual(night.sleepStart, APIClient.parseInstant("2026-10-08T21:34:00Z"))
        XCTAssertNil(night.hrvRmssdMs)
        XCTAssertEqual(night.wristTemperatureCelsius, 35.84)
        XCTAssertEqual(night.source, "ios")
        XCTAssertNil(nights[1].wristTemperatureCelsius, "eine Nacht von vor dem 22.10. hat keine")
    }

    /// Was `POST /api/nights` bekommt: die Temperatur unter ihrem Namen aus
    /// dem Vertrag §2.1; ohne Messung fehlt das Feld (= unbekannt).
    func testEncodesWristTemperature() throws {
        func json(_ temperature: Double?) throws -> [String: Any] {
            let night = Night(date: CalendarDate(year: 2026, month: 10, day: 9), sleepStart: nil, sleepEnd: nil,
                              asleepMinutes: 431, inBedMinutes: nil, awakeMinutes: nil, deepMinutes: nil,
                              remMinutes: nil, coreMinutes: nil, hrvSdnnMs: 48.3, hrvSdnnSamples: 4,
                              hrvRmssdMs: nil, hrvRmssdSamples: nil, sleepingHeartRate: 52.4,
                              respiratoryRate: 14.2, wristTemperatureCelsius: temperature, source: "ios")
            let data = try APIClient.encoder().encode(NightsUpload(nights: [night]))
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try XCTUnwrap((body["nights"] as? [[String: Any]])?.first)
        }
        XCTAssertEqual(try json(35.84)["wristTemperatureCelsius"] as? Double, 35.84)
        XCTAssertNil(try json(nil)["wristTemperatureCelsius"])
    }

    // MARK: - Kalorienzaehler seit 10.11. (Vertrag §11)

    /// `GET /api/food/targets` - das Beispiel aus dem Vertrag §11.1.
    func testDecodesTargetsWithProteinFloor() throws {
        let targets = try decode(Nutrients.self, """
        {"kcal":2300.0,"proteinG":195.0,"carbsG":236.0,"fatG":70.0,"proteinMinG":140.0,"proteinMinDefault":false}
        """)
        XCTAssertEqual(targets.proteinG, 195)
        XCTAssertEqual(targets.proteinMinG, 140)
        XCTAssertEqual(targets.proteinMinDefault, false)

        // Niemand hat einen Erhalt gesetzt: der Dienst rechnet ihn aus dem Ziel.
        let byDefault = try decode(Nutrients.self, """
        {"kcal":2300.0,"proteinG":200.0,"carbsG":235.5,"fatG":62.0,"proteinMinG":145.0,"proteinMinDefault":true}
        """)
        XCTAssertEqual(byDefault.proteinMinDefault, true)
    }

    /// `POST /api/food/devices` (§11.2): Healthy nennt die Umgebung; die
    /// Anmeldungen bei To-Do und Noten bleiben, wie sie waren.
    func testDeviceRegistrationNamesTheEnvironment() throws {
        func json(_ registration: DeviceRegistration) throws -> [String: Any] {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: APIClient.encoder().encode(registration))
                          as? [String: Any])
        }
        let healthy = try json(DeviceRegistration(token: "abc", environment: APNsEnvironment.production.rawValue))
        XCTAssertEqual(healthy["token"] as? String, "abc")
        XCTAssertEqual(healthy["environment"] as? String, "production")
        let other = try json(DeviceRegistration(token: "abc"))
        XCTAssertEqual(other.count, 1, "ohne Umgebung bleibt das Feld weg")
    }

    /// `GET /api/food/features`: `me` nennt die Person des Zugangs; ein
    /// aelterer Dienst kennt das Feld nicht.
    func testDecodesFeaturesWithAndWithoutTheName() throws {
        let named = try decode(Features.self, #"{"quickCapture":true,"me":"person-a"}"#)
        XCTAssertEqual(named.me, "person-a")
        XCTAssertTrue(named.quickCapture)
        XCTAssertNil(try decode(Features.self, #"{"quickCapture":false}"#).me)
    }

    // MARK: - Strain (Vertrag §7)

    /// `StrainDayView` - das Beispiel aus dem Vertrag §7.3.
    func testDecodesStrainDay() throws {
        let day = try decode(StrainDay.self, """
        {"date":"2026-11-09","status":"OK","partial":false,"coverageMinutes":1312,"covered":true,
         "load":142.6,"strain":13.4,"band":"MODERATE","targetLoad":120.3,"targetStrain":12.1,
         "acuteLoad":118.2,"chronicLoad":110.5,"recoveryScore":65,"recoveryBand":"GREEN",
         "hrRest":52.4,"hrMax":188.0,"calibration":{"days":22,"required":14}}
        """)
        XCTAssertEqual(day.date, CalendarDate(year: 2026, month: 11, day: 9))
        XCTAssertEqual(day.status, .ok)
        XCTAssertFalse(day.partial)
        XCTAssertEqual(day.coverageMinutes, 1312)
        XCTAssertTrue(day.covered)
        XCTAssertEqual(day.load, 142.6)
        XCTAssertEqual(day.strain, 13.4)
        XCTAssertEqual(day.band, .moderate)
        XCTAssertEqual(day.targetLoad, 120.3)
        XCTAssertEqual(day.targetStrain, 12.1)
        XCTAssertEqual(day.acuteLoad, 118.2)
        XCTAssertEqual(day.chronicLoad, 110.5)
        XCTAssertEqual(day.recoveryScore, 65)
        XCTAssertEqual(day.recoveryBand, .green)
        XCTAssertEqual(day.hrRest, 52.4)
        XCTAssertEqual(day.hrMax, 188)
        XCTAssertEqual(day.calibration, StrainCalibration(days: 22, required: 14))
    }

    /// Ein Tag ohne Histogramm (`NO_DATA`): Last, Strain, Band und Abdeckung
    /// fehlen - die Werte des Morgens (Ziel, Akut, Gewohnt, Recovery) stehen
    /// trotzdem da (§7.3). Heute ist `partial`.
    func testDecodesStrainDayWithoutAHistogram() throws {
        let day = try decode(StrainDay.self, """
        {"date":"2026-11-10","status":"NO_DATA","partial":true,"coverageMinutes":null,"covered":false,
         "load":null,"strain":null,"band":null,"targetLoad":118.9,"targetStrain":12.0,
         "acuteLoad":121.4,"chronicLoad":111.0,"recoveryScore":null,"recoveryBand":null,
         "hrRest":52.4,"hrMax":188.0,"calibration":{"days":22,"required":14}}
        """)
        XCTAssertEqual(day.status, .noData)
        XCTAssertTrue(day.partial)
        XCTAssertNil(day.coverageMinutes)
        XCTAssertNil(day.strain)
        XCTAssertNil(day.band)
        XCTAssertEqual(day.targetStrain, 12.0)
        XCTAssertEqual(day.acuteLoad, 121.4)
        XCTAssertNil(day.recoveryBand)
    }

    /// Beim Kalibrieren gibt es noch kein Ziel; ein vergangener Tag mit wenig
    /// Puls ist `LOW_COVERAGE`. Und was der Dienst spaeter Neues schickt -
    /// einen Status, ein Band -, macht den Tag nicht unlesbar; fehlende Felder
    /// auch nicht.
    func testStrainDayToleratesWhatItDoesNotKnow() throws {
        let calibrating = try decode(StrainDay.self, """
        {"date":"2026-11-02","status":"CALIBRATING","partial":false,"coverageMinutes":1280,"covered":true,
         "load":96.0,"strain":10.4,"band":"MODERATE","targetLoad":null,"targetStrain":null,
         "acuteLoad":90.2,"chronicLoad":88.0,"recoveryScore":null,"recoveryBand":null,
         "hrRest":52.4,"hrMax":170.0,"calibration":{"days":9,"required":14}}
        """)
        XCTAssertEqual(calibrating.status, .calibrating)
        XCTAssertNil(calibrating.targetStrain)
        XCTAssertEqual(calibrating.calibration?.days, 9)

        let low = try decode(StrainDay.self, """
        {"date":"2026-11-01","status":"LOW_COVERAGE","partial":false,"coverageMinutes":412,"covered":false,
         "load":31.0,"strain":4.2,"band":"LIGHT","hrMax":170.0}
        """)
        XCTAssertEqual(low.status, .lowCoverage)
        XCTAssertEqual(low.band, .light)
        XCTAssertFalse(low.covered)
        XCTAssertNil(low.calibration)

        let newer = try decode(StrainDay.self, """
        {"date":"2026-11-03","status":"SOMETHING_NEW","strain":19.2,"band":"BEYOND","recoveryBand":"BLUE",
         "coverageMinutes":1301.6}
        """)
        XCTAssertEqual(newer.status, .unknown)
        XCTAssertEqual(newer.band, .unknown)
        XCTAssertEqual(newer.recoveryBand, .unknown)
        XCTAssertFalse(newer.partial)
        XCTAssertEqual(newer.coverageMinutes, 1302)
        XCTAssertEqual(try decode(StrainDay.self, #"{"date":"2026-11-03","status":"OK","strain":18.0,"band":"ALL_OUT"}"#).band,
                       .allOut)
        XCTAssertEqual(try decode(StrainDay.self, #"{"date":"2026-11-03","status":"OK","strain":14.0,"band":"HIGH"}"#).band,
                       .high)
    }

    /// `GET /api/strain` liefert die Tage als Liste; ohne einen gespeicherten
    /// Tag ist sie leer.
    func testDecodesStrainRange() throws {
        XCTAssertTrue(try decode([StrainDay].self, "[]").isEmpty)
        let days = try decode([StrainDay].self, """
        [{"date":"2026-11-08","status":"OK","partial":false,"coverageMinutes":1290,"covered":true,
          "load":80.1,"strain":9.1,"band":"MODERATE","hrMax":188.0},
         {"date":"2026-11-09","status":"NO_DATA","partial":false,"covered":false,"hrMax":188.0}]
        """)
        XCTAssertEqual(days.map(\.status), [.ok, .noData])
    }

    /// `StrainSettingsView` - das Beispiel aus dem Vertrag §7.5, und der Stand
    /// ohne Histogramme.
    func testDecodesStrainSettings() throws {
        let settings = try decode(StrainSettings.self, """
        {"hrMax":188,"hrMaxUsed":188.0,"hrMaxSource":"SETTING","hrMaxObserved":184.5,"hrRest":52.4,
         "hrRestSource":"NIGHTS","tau":140}
        """)
        XCTAssertEqual(settings.hrMax, 188)
        XCTAssertEqual(settings.hrMaxUsed, 188)
        XCTAssertEqual(settings.hrMaxSource, .setting)
        XCTAssertEqual(settings.hrMaxObserved, 184.5)
        XCTAssertEqual(settings.hrRest, 52.4)
        XCTAssertEqual(settings.hrRestSource, .nights)
        XCTAssertEqual(settings.tau, 140)

        let fresh = try decode(StrainSettings.self, """
        {"hrMax":null,"hrMaxUsed":170.0,"hrMaxSource":"DEFAULT","hrMaxObserved":null,"hrRest":null,
         "hrRestSource":"NONE","tau":140.0}
        """)
        XCTAssertNil(fresh.hrMax)
        XCTAssertEqual(fresh.hrMaxSource, .standard)
        XCTAssertEqual(fresh.hrRestSource, .missing)
        XCTAssertEqual(try decode(StrainSettings.self, """
        {"hrMaxUsed":181.0,"hrMaxSource":"OBSERVED","hrMaxObserved":181.0,"hrRest":58.0,
         "hrRestSource":"HISTOGRAM","tau":140.0}
        """).hrRestSource, .histogram)
    }

    /// `PUT /api/strain/settings`: ein festgelegter Maximalpuls geht als Zahl,
    /// die Freigabe als fehlendes Feld - der Dienst liest beides (§7.5).
    func testStrainSettingsRequest() throws {
        func json(_ request: StrainSettingsRequest) throws -> [String: Any] {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: APIClient.encoder().encode(request))
                          as? [String: Any])
        }
        XCTAssertEqual(try json(StrainSettingsRequest(hrMax: 188))["hrMax"] as? Double, 188)
        XCTAssertTrue(try json(StrainSettingsRequest(hrMax: nil)).isEmpty)
    }

    /// `POST /api/strain` - das Beispiel aus dem Vertrag §7.1, und die Antwort
    /// mit dem gespeicherten Stand.
    func testHeartUploadAndItsAnswer() throws {
        let upload = HeartUpload(days: [HeartDayUpload(date: CalendarDate(year: 2026, month: 11, day: 9),
                                                       coverageMinutes: 401.7, fromBpm: 40,
                                                       minutes: [12.5, 88.0, 301.2])], replace: nil)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: APIClient.encoder().encode(upload))
                                 as? [String: Any])
        let expected = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data("""
        {"days":[{"date":"2026-11-09","coverageMinutes":401.7,"fromBpm":40,"minutes":[12.5,88.0,301.2]}]}
        """.utf8)) as? [String: Any])
        XCTAssertEqual(sent as NSDictionary, expected as NSDictionary)

        let stored = try decode([StrainStored].self, #"[{"date":"2026-11-09","coverageMinutes":1312.4}]"#)
        XCTAssertEqual(stored, [StrainStored(date: CalendarDate(year: 2026, month: 11, day: 9),
                                             coverageMinutes: 1312.4)])
    }

    // MARK: - Eichungs-Monitor (Vertrag §1.6)

    /// `calibrationMonitor` in der Summary - das Beispiel aus dem Vertrag §1.6.
    /// Ein Dienst von vor dem Feld schickt es nicht (siehe `testDecodesEnergySummary`).
    func testDecodesCalibrationMonitor() throws {
        let monitor = try decode(CalibrationMonitor.self, """
        {"status":"OK","factor":0.957,"se":0.031,"windowFrom":"2026-09-15","windowTo":"2026-11-09",
         "weights":41,"trackedDays":50,"imputedIntakeDays":6,"watchDays":55,"waterKgPer1000Kcal":0.21}
        """)
        XCTAssertEqual(monitor.status, .ok)
        XCTAssertEqual(monitor.factor, 0.957)
        XCTAssertEqual(monitor.se, 0.031)
        XCTAssertEqual(monitor.windowFrom, CalendarDate(year: 2026, month: 9, day: 15))
        XCTAssertEqual(monitor.imputedIntakeDays, 6)

        let without = try decode(CalibrationMonitor.self, """
        {"status":"TOO_FEW_WEIGHTS","factor":null,"se":null,"windowFrom":"2026-09-15","windowTo":"2026-11-09",
         "weights":12,"trackedDays":50,"imputedIntakeDays":6,"watchDays":55,"waterKgPer1000Kcal":null}
        """)
        XCTAssertEqual(without.status, .tooFewWeights)
        XCTAssertNil(without.factor)
        XCTAssertEqual(try decode(CalibrationMonitor.self, #"{"status":"NEU","factor":null,"se":null}"#).status,
                       .unknown)
    }

    /// Die Summary traegt den Monitor neben der Kalibrierung; ohne das Feld
    /// (aelterer Dienst) bleibt sie lesbar.
    func testEnergySummaryCarriesTheMonitor() throws {
        let body = """
        {"today":null,"deficit7":null,"deficit7Days":0,"expenditure7":null,"expenditure7Days":0,
         "calibration":{"status":"FIXED","factor":0.93,"rawFactor":0.807,"windowFrom":"2026-10-13",
           "windowTo":"2026-11-09","measuredKcal":2651.0,"measuredSeKcal":160.0,"watchKcal":3287.0,
           "intakeKcal":2913.0,"weightSlopeKgPerWeek":0.238,"trackedDays":28,"weightDays":27,"watchDays":28},
         MONITOR"sources":{"food":"OK"}}
        """
        let with = try decode(EnergySummary.self, body.replacingOccurrences(
            of: "MONITOR", with: #""calibrationMonitor":{"status":"OK","factor":0.957,"se":0.031},"#))
        XCTAssertEqual(with.calibration.status, .fixed)
        XCTAssertEqual(with.calibrationMonitor?.factor, 0.957)
        XCTAssertNil(try decode(EnergySummary.self, body.replacingOccurrences(of: "MONITOR", with: ""))
            .calibrationMonitor)
    }

    // MARK: - Freischaltungen, Chat, Briefing (Vertrag §8)

    /// `GET /api/features` - und ein Dienst, der ein Feld noch nicht kennt.
    func testDecodesHealthFeatures() throws {
        let features = try decode(HealthFeatures.self,
                                  #"{"me":"person-a","chat":true,"briefing":true,"friends":true}"#)
        XCTAssertEqual(features, HealthFeatures(me: "person-a", chat: true, briefing: true, friends: true))
        XCTAssertEqual(try decode(HealthFeatures.self, #"{"me":"person-a"}"#),
                       HealthFeatures(me: "person-a"), "was fehlt, ist aus")
    }

    /// `ChatView` - Fragen mit Antwort, aelteste zuerst; Zeitpunkte mit
    /// Bruchteilen von Sekunden, wie der Dienst sie schreibt.
    func testDecodesChat() throws {
        let chat = try decode(ChatState.self, """
        {"available":true,"exchanges":[
          {"id":"00000000-0000-4000-8000-0000000000aa","question":"Was sollte ich heute noch essen?",
           "askedAt":"2026-11-10T17:02:11Z","status":"DONE","answer":"Antwort.",
           "answeredAt":"2026-11-10T17:02:40.791736Z","error":null,"elapsedSeconds":29},
          {"id":"00000000-0000-4000-8000-0000000000ab","question":"Und morgen?",
           "askedAt":"2026-11-10T12:39:55.700686Z","status":"RUNNING","answer":null,
           "answeredAt":null,"error":null,"elapsedSeconds":3}],
         "limits":{"perDay":30,"usedToday":7,"maxChars":1000}}
        """)
        XCTAssertTrue(chat.available)
        XCTAssertEqual(chat.exchanges.map(\.status), [.done, .running])
        XCTAssertEqual(chat.exchanges[0].answer, "Antwort.")
        XCTAssertEqual(chat.exchanges[0].elapsedSeconds, 29)
        let asked = try XCTUnwrap(chat.exchanges[0].askedAt)
        let answered = try XCTUnwrap(chat.exchanges[0].answeredAt)
        XCTAssertEqual(answered.timeIntervalSince(asked), 29, accuracy: 0.001)
        XCTAssertNotNil(chat.exchanges[1].askedAt, "auch mit Bruchteilen lesbar")
        XCTAssertEqual(chat.limits, ChatLimits(perDay: 30, usedToday: 7, maxChars: 1000))
    }

    /// Eine gescheiterte Frage traegt ihren Satz; ein Status, den die App
    /// nicht kennt, macht das Gespraech nicht unlesbar; ein leerer Chat ist leer.
    func testDecodesFailedAndUnknownExchanges() throws {
        let failed = try decode(ChatExchange.self, """
        {"id":"x","question":"Frage","askedAt":"2026-11-10T17:02:11Z","status":"FAILED","answer":null,
         "answeredAt":"2026-11-10T17:04:11Z",
         "error":"Die Anmeldung von Claude auf dem Server ist abgelaufen.","elapsedSeconds":120}
        """)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.error, "Die Anmeldung von Claude auf dem Server ist abgelaufen.")
        XCTAssertEqual(try decode(ChatExchange.self, #"{"id":"y","question":"Frage","status":"NEU"}"#).status,
                       .unknown)
        let empty = try decode(ChatState.self, #"{"available":false,"exchanges":[]}"#)
        XCTAssertFalse(empty.available)
        XCTAssertTrue(empty.exchanges.isEmpty)
        XCTAssertNil(empty.limits)
    }

    /// `POST /api/chat/messages` - Kennung und Text, sonst nichts.
    func testChatSend() throws {
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APIClient.encoder().encode(ChatSend(id: "00000000-0000-4000-8000-0000000000aa", text: "Frage")))
            as? [String: String])
        XCTAssertEqual(sent, ["id": "00000000-0000-4000-8000-0000000000aa", "text": "Frage"])
    }

    /// `BriefingView` - fertig, laufend (mit dem alten Text) und ohne.
    func testDecodesBriefing() throws {
        let done = try decode(Briefing.self, """
        {"date":"2026-11-10","status":"DONE","text":"Zwei Sätze.","generatedAt":"2026-11-10T12:39:58.794697Z"}
        """)
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.text, "Zwei Sätze.")
        XCTAssertEqual(done.date, CalendarDate(year: 2026, month: 11, day: 10))
        XCTAssertNotNil(done.generatedAt)

        let running = try decode(Briefing.self,
                                 #"{"date":"2026-11-10","status":"RUNNING","text":null,"generatedAt":null}"#)
        XCTAssertEqual(running.status, .running)
        XCTAssertNil(running.text)
        XCTAssertEqual(try decode(Briefing.self, #"{"date":"2026-11-10","status":"NONE"}"#).status, BriefingStatus.none)
        XCTAssertEqual(try decode(Briefing.self, #"{"status":"NEU"}"#).status, .unknown)
    }

    // MARK: - Wochenrueckblick (Vertrag §9)

    /// `WeekReview` - das Beispiel aus dem Vertrag; ohne Kalorienzaehler
    /// fehlen Aufnahme, Defizit und Eiweiss-Tage, der Rest steht da.
    func testDecodesWeekReview() throws {
        let review = try decode(WeekReview.self, """
        {"week":{"from":"2026-11-02","to":"2026-11-08","kcalAvg":2180.0,"deficitAvg":410.0,"trackedDays":6,
          "weightAvg":91.4,"weightDays":6,"weightDeltaKg":-0.42,
          "proteinGreenDays":4,"proteinYellowDays":1,"proteinRedDays":1,
          "stepsAvg":9120.0,"stepsDays":7,"strainAvg":11.8,"strainDays":6},
         "previous":{"from":"2026-10-26","to":"2026-11-01","kcalAvg":null,"deficitAvg":null,"trackedDays":0,
          "weightAvg":91.8,"weightDays":5,"weightDeltaKg":null,
          "proteinGreenDays":0,"proteinYellowDays":0,"proteinRedDays":0,
          "stepsAvg":8800.0,"stepsDays":7,"strainAvg":null,"strainDays":0},
         "sources":{"food":"OK"}}
        """)
        XCTAssertEqual(review.week.from, CalendarDate(year: 2026, month: 11, day: 2))
        XCTAssertEqual(review.week.kcalAvg, 2180)
        XCTAssertEqual(review.week.weightDeltaKg, -0.42)
        XCTAssertEqual(review.week.proteinGreenDays, 4)
        XCTAssertEqual(review.week.strainAvg, 11.8)
        XCTAssertNil(review.previous?.kcalAvg)
        XCTAssertEqual(review.previous?.stepsAvg, 8800)
        XCTAssertEqual(review.sources?["food"], "OK")
    }

    // MARK: - Freunde und Serien (Vertrag §10)

    /// `FriendsView` - das Beispiel aus dem Vertrag §10.1 mit allen vier Serien.
    func testDecodesFriends() throws {
        let overview = try decode(FriendsOverview.self, """
        {"me":{"person":"person-a","name":"Person A"},
         "friends":[{"id":"f-3k9x","person":"person-b","name":"Person B","since":"2026-11-10",
           "today":{"tracked":true,"recoveryBand":"GREEN","strainBand":"MODERATE"},
           "streaks":[{"type":"TRACKED","current":12,"best":30,"me":"DONE","friend":"OPEN","atRisk":true},
                      {"type":"PROTEIN","current":0,"best":4,"me":"OPEN","friend":"OPEN","atRisk":false},
                      {"type":"STEPS","current":3,"best":9,"me":"DONE","friend":"DONE","atRisk":false},
                      {"type":"KCAL","current":1,"best":6,"me":"FAILED","friend":"UNKNOWN","atRisk":false}],
           "steps":{"weekStart":"2026-11-09","days":[{"date":"2026-11-09","me":8123,"friend":10450},
                                                    {"date":"2026-11-10","me":5200,"friend":null}],
                    "me":13323,"friend":10450,"lastWeek":{"me":71200,"friend":69800}},
           "nudge":{"allowed":true}}],
         "invites":[{"code":"K7Q4-M2XD","expiresAt":"2026-11-17T18:00:00.123456Z"}]}
        """)
        XCTAssertEqual(overview.me?.name, "Person A")
        let friend = try XCTUnwrap(overview.friends.first)
        XCTAssertEqual(friend.id, "f-3k9x")
        XCTAssertEqual(friend.name, "Person B")
        XCTAssertEqual(friend.since, CalendarDate(year: 2026, month: 11, day: 10))
        XCTAssertEqual(friend.today, FriendToday(tracked: true, recoveryBand: .green, strainBand: .moderate))
        XCTAssertEqual(friend.streaks.map(\.type), [.tracked, .protein, .steps, .kcal])
        XCTAssertEqual(friend.streaks[0],
                       FriendStreak(type: .tracked, current: 12, best: 30, me: .done, friend: .open, atRisk: true))
        XCTAssertEqual(friend.streaks[3].me, .failed)
        XCTAssertEqual(friend.streaks[3].friend, .unknown)
        XCTAssertEqual(friend.steps?.days.count, 2)
        XCTAssertNil(friend.steps?.days[1].friend)
        XCTAssertEqual(friend.steps?.lastWeek, FriendStepsTotals(me: 71200, friend: 69800))
        XCTAssertTrue(friend.nudge.allowed)
        XCTAssertEqual(overview.invites.first?.code, "K7Q4-M2XD")
        XCTAssertNotNil(overview.invites.first?.expiresAt)
    }

    /// Ohne Recovery und Strain sind die Baender `null`; Arten und Zustaende,
    /// die die App noch nicht kennt, machen die Antwort nicht unlesbar.
    func testFriendsTolerateWhatTheyDoNotKnow() throws {
        let friend = try decode(Friend.self, """
        {"id":"f-1","person":"person-a","name":"Person A","since":"2026-11-10",
         "today":{"tracked":false,"recoveryBand":null,"strainBand":"NEU"},
         "streaks":[{"type":"SLEEP","current":2,"best":2,"me":"PAUSED","friend":"DONE","atRisk":false}],
         "steps":{"weekStart":"2026-11-09","days":[],"me":0,"friend":0,"lastWeek":{"me":0,"friend":0}},
         "nudge":{"allowed":false}}
        """)
        XCTAssertNil(friend.today.recoveryBand)
        XCTAssertEqual(friend.today.strainBand, .unknown)
        XCTAssertEqual(friend.streaks[0].type, .unknown)
        XCTAssertEqual(friend.streaks[0].me, .unknown)
        XCTAssertTrue(friend.shownStreaks.isEmpty)
        XCTAssertFalse(friend.nudge.allowed)
        XCTAssertEqual(try decode(FriendsOverview.self, #"{"friends":[]}"#), FriendsOverview())
    }

    /// `POST /api/friends/invites`, `POST /api/friends`, der Stupser und die
    /// Kachel `GET /api/streaks` - mit und ohne Freundes-Serie.
    func testDecodesInviteNudgeAndStreakTile() throws {
        let invite = try decode(FriendInvite.self, #"{"code":"K7Q4-M2XD","expiresAt":"2026-11-17T18:00:00Z"}"#)
        XCTAssertEqual(invite.code, "K7Q4-M2XD")
        XCTAssertFalse(try decode(NudgeResult.self, #"{"delivered":false}"#).delivered)
        let accept = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APIClient.encoder().encode(FriendAcceptRequest(code: "K7Q4-M2XD"))) as? [String: String])
        XCTAssertEqual(accept, ["code": "K7Q4-M2XD"])

        let tile = try decode(StreakTile.self, """
        {"tracking":{"current":23,"best":41,"todayDone":false},
         "topFriend":{"friendshipId":"f-3k9x","name":"Person B","type":"STEPS","current":12,"atRisk":true}}
        """)
        XCTAssertEqual(tile.tracking?.current, 23)
        XCTAssertEqual(tile.topFriend?.name, "Person B")
        XCTAssertEqual(tile.topFriend?.type, .steps)
        XCTAssertEqual(tile.topFriend?.atRisk, true)
        let alone = try decode(StreakTile.self,
                               #"{"tracking":{"current":40,"best":40,"todayDone":false},"topFriend":null}"#)
        XCTAssertNil(alone.topFriend)
        XCTAssertEqual(alone.tracking?.best, 40)
    }
}
