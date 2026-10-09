import XCTest
@testable import Healthy

/// Die Regeln aus dem Vertrag (`weight-app/docs/HEALTHY-CONTRACT.md` §2.2) -
/// mit erfundenen Segmenten, ohne HealthKit. Die Abfragen selbst lassen sich
/// nicht pruefen; was daraus eine Nacht macht, schon.
final class HealthNightsTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let october9 = CalendarDate(year: 2026, month: 10, day: 9)

    /// Ortszeit in Berlin - auch ueber die Zeitumstellung hinweg.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    private func segment(_ start: Date, _ end: Date, _ stage: SleepSegment.Stage = .core,
                         source: String = "com.apple.health.watch", watch: Bool = true) -> SleepSegment {
        SleepSegment(start: start, end: end, stage: stage, source: source, isWatch: watch)
    }

    private func mains(_ segments: [SleepSegment], _ days: [CalendarDate]) -> [MainSleep] {
        HealthNights.mainSleeps(segments, days: days, timeZone: berlin)
    }

    private func night(_ main: MainSleep, inBed: [SleepSegment] = [], sdnn: [HealthReading] = [],
                       rmssd: [HealthReading]? = nil, breathing: [HealthReading] = [],
                       heart: Double? = nil) -> Night? {
        HealthNights.night(main, inBed: inBed, hrvSdnn: sdnn, hrvRmssd: rmssd,
                           respiratory: breathing, sleepingHeartRate: heart)
    }

    private func reading(_ start: Date, _ value: Double, watch: Bool = true) -> HealthReading {
        HealthReading(start: start, value: value, isWatch: watch)
    }

    // MARK: - Phasen

    /// 89 Minuten wach in der Nacht trennen nicht - das ist dieselbe Nacht.
    func testGapOf89MinutesStaysOnePhase() throws {
        let found = mains([segment(at(8, 23), at(9, 2)), segment(at(9, 3, 29), at(9, 7))], [october9])
        let main = try XCTUnwrap(found.first)
        XCTAssertEqual(main.start, at(8, 23))
        XCTAssertEqual(main.end, at(9, 7))
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 180 + 211)
    }

    /// 91 Minuten trennen: zwei Phasen, und die laengere ist die Nacht.
    func testGapOf91MinutesSplitsAndTheLongerPhaseWins() throws {
        let found = mains([segment(at(9, 0), at(9, 4)), segment(at(9, 5, 31), at(9, 6, 31))], [october9])
        let main = try XCTUnwrap(found.first)
        XCTAssertEqual(main.start, at(9, 0))
        XCTAssertEqual(main.end, at(9, 4))
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 240)
    }

    /// Ein Mittagsschlaf beginnt nach 12:00 - er ist keine Nacht, weder fuer
    /// diesen Tag noch fuer den naechsten.
    func testAfternoonNapIsNoNight() throws {
        let segments = [segment(at(8, 23), at(9, 6, 30)), segment(at(9, 14), at(9, 15))]
        let found = mains(segments, [october9, october9.adding(days: 1)])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.date, october9)
        XCTAssertEqual(found.first?.end, at(9, 6, 30))
    }

    /// Ein Nickerchen am Vormittag erfuellt die Regel auch - aber die Nacht hat
    /// mehr Schlafminuten.
    func testMorningNapDoesNotReplaceTheNight() throws {
        let segments = [segment(at(8, 23), at(9, 6)), segment(at(9, 9), at(9, 10))]
        let main = try XCTUnwrap(mains(segments, [october9]).first)
        XCTAssertEqual(main.start, at(8, 23))
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 420)
    }

    /// Wer erst nach Mitternacht einschlaeft, hat trotzdem die Nacht dieses
    /// Morgens.
    func testSleepAfterMidnightBelongsToThatMorning() throws {
        let main = try XCTUnwrap(mains([segment(at(9, 0, 45), at(9, 7, 15))], [october9]).first)
        XCTAssertEqual(main.date, october9)
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 390)
    }

    /// Endet eine Phase vor 03:00 oder nach 16:00, ist sie keine Nacht fuer
    /// diesen Tag.
    func testPhaseMustEndBetweenThreeAndFourPM() {
        XCTAssertTrue(mains([segment(at(8, 21), at(9, 2, 30))], [october9]).isEmpty)
        XCTAssertTrue(mains([segment(at(9, 11), at(9, 16, 30))], [october9]).isEmpty)
        XCTAssertEqual(mains([segment(at(9, 11), at(9, 16))], [october9]).count, 1,
                       "16:00 genau gilt noch")
    }

    /// In der Nacht vom 24. auf den 25.10.2026 wird die Uhr zurueckgestellt:
    /// von 23:00 bis 07:00 Ortszeit sind es neun Stunden, nicht acht.
    func testNightAcrossTheEndOfSummerTimeIsAnHourLonger() throws {
        let morning = CalendarDate(year: 2026, month: 10, day: 25)
        let main = try XCTUnwrap(mains([segment(at(24, 23), at(25, 7))], [morning]).first)
        XCTAssertEqual(main.date, morning)
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 540)
    }

    // MARK: - Quellen

    /// Hat die Uhr eine Nacht, gilt nur sie - auch wenn das iPhone laenger
    /// „Schlaf" geschrieben hat. Zusammengelegt zaehlte die Nacht doppelt.
    func testWatchWinsOverTheIPhone() throws {
        let segments = [
            segment(at(8, 23, 30), at(9, 6, 30)),
            segment(at(8, 22), at(9, 7), .unspecified, source: "com.apple.health.iphone", watch: false),
        ]
        let main = try XCTUnwrap(mains(segments, [october9]).first)
        XCTAssertEqual(main.start, at(8, 23, 30))
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 420)
    }

    /// Ohne Uhr gilt die eine Quelle mit den meisten Schlafminuten - zwei
    /// Apps werden nie zu einer Nacht vereinigt.
    func testTwoOtherSourcesAreNeverMerged() throws {
        let segments = [
            segment(at(8, 23), at(9, 3), .unspecified, source: "app.a", watch: false),
            segment(at(9, 2), at(9, 7), .unspecified, source: "app.b", watch: false),
        ]
        let main = try XCTUnwrap(mains(segments, [october9]).first)
        XCTAssertEqual(main.start, at(9, 2))
        XCTAssertEqual(try XCTUnwrap(night(main)).asleepMinutes, 300, "nicht 480 aus beiden")
    }

    /// Schlaeft die Uhr am Ladekabel, kommt die Nacht vom iPhone.
    func testWithoutTheWatchTheIPhoneCounts() throws {
        let segments = [segment(at(8, 22), at(9, 6), .unspecified, source: "com.apple.health.iphone", watch: false)]
        XCTAssertEqual(mains(segments, [october9]).first?.start, at(8, 22))
    }

    // MARK: - Was in der Nacht steht

    /// Ueberlappende Segmente einer Quelle zaehlen einmal; die Stadien je fuer
    /// sich, Wachzeit in der Phase extra.
    func testStagesAreUnionsAndAwakeIsCountedApart() throws {
        let segments = [
            segment(at(8, 23), at(9, 1)),
            segment(at(9, 1), at(9, 2), .deep),
            segment(at(9, 2), at(9, 2, 30), .awake),
            segment(at(9, 2, 30), at(9, 4), .rem),
            segment(at(9, 3, 30), at(9, 6)),
        ]
        let main = try XCTUnwrap(mains(segments, [october9]).first)
        let result = try XCTUnwrap(night(main))
        XCTAssertEqual(result.asleepMinutes, 120 + 60 + 210)
        XCTAssertEqual(result.coreMinutes, 120 + 150)
        XCTAssertEqual(result.deepMinutes, 60)
        XCTAssertEqual(result.remMinutes, 90)
        XCTAssertEqual(result.awakeMinutes, 30)
        XCTAssertEqual(result.source, "ios")
    }

    /// Eine Quelle ohne Stadien kennt weder Tief- noch REM-Schlaf - dann steht
    /// dort „unbekannt", keine Null.
    func testStagesAreUnknownWithoutStages() throws {
        let segments = [segment(at(8, 23), at(9, 7), .unspecified, source: "app.a", watch: false)]
        let main = try XCTUnwrap(mains(segments, [october9]).first)
        let result = try XCTUnwrap(night(main))
        XCTAssertNil(result.deepMinutes)
        XCTAssertNil(result.remMinutes)
        XCTAssertNil(result.coreMinutes)
        XCTAssertNil(result.awakeMinutes)
        XCTAssertNil(result.inBedMinutes)
    }

    /// „Im Bett" darf aus jeder Quelle kommen; vereinigt zaehlt nichts doppelt.
    func testInBedComesFromAnySource() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6, 30))], [october9]).first)
        let bed = [
            segment(at(8, 22, 30), at(9, 7), .inBed, source: "com.apple.health.iphone", watch: false),
            segment(at(8, 22, 45), at(9, 6, 45), .inBed),
            segment(at(9, 14), at(9, 15), .inBed, source: "app.a", watch: false),
        ]
        XCTAssertEqual(try XCTUnwrap(night(main, inBed: bed)).inBedMinutes, 510)
    }

    // MARK: - HRV, Atem, Puls

    /// Messungen, die zwischen Schlafbeginn und 30 Minuten nach dem Aufwachen
    /// beginnen - davor und danach nicht.
    func testHrvWindowReachesThirtyMinutesPastWaking() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let readings = [reading(at(8, 22, 59), 10), reading(at(8, 23), 40),
                        reading(at(9, 6, 29), 90), reading(at(9, 6, 31), 200)]
        let result = try XCTUnwrap(night(main, sdnn: readings))
        XCTAssertEqual(result.hrvSdnnMs, 60, "geometrisches Mittel aus 40 und 90")
        XCTAssertEqual(result.hrvSdnnSamples, 2)
        XCTAssertNil(result.hrvRmssdMs, "ohne RMSSD (vor iOS 27) unbekannt")
    }

    func testHrvDropsValuesAtOrBelowZero() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let readings = [reading(at(9, 1), 0), reading(at(9, 2), -5), reading(at(9, 3), 50)]
        let result = try XCTUnwrap(night(main, sdnn: readings))
        XCTAssertEqual(result.hrvSdnnMs, 50)
        XCTAssertEqual(result.hrvSdnnSamples, 1)
    }

    /// Misst die Uhr, zaehlen nur ihre Werte; sonst alle.
    func testHrvPrefersTheWatch() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let mixed = [reading(at(9, 1), 30), reading(at(9, 2), 100, watch: false)]
        XCTAssertEqual(try XCTUnwrap(night(main, sdnn: mixed)).hrvSdnnMs, 30)
        let phoneOnly = [reading(at(9, 2), 100, watch: false)]
        XCTAssertEqual(try XCTUnwrap(night(main, sdnn: phoneOnly)).hrvSdnnMs, 100)
    }

    /// RMSSD (ab iOS 27) und SDNN stehen getrennt - welche zaehlt, entscheidet
    /// der Dienst.
    func testBothHrvMethodsAreSentSeparately() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let result = try XCTUnwrap(night(main, sdnn: [reading(at(9, 1), 45)],
                                         rmssd: [reading(at(9, 1), 32), reading(at(9, 2), 50)]))
        XCTAssertEqual(result.hrvSdnnMs, 45)
        XCTAssertEqual(result.hrvRmssdMs, 40)
        XCTAssertEqual(result.hrvRmssdSamples, 2)
    }

    func testGeometricMean() {
        XCTAssertEqual(try XCTUnwrap(HealthNights.geometricMean([25, 100])), 50, accuracy: 1e-9)
        XCTAssertNil(HealthNights.geometricMean([]))
        XCTAssertNil(HealthNights.geometricMean([0, -1]))
    }

    /// Atemfrequenz: das Mittel der Messungen, die in der Phase beginnen.
    /// Puls und Atem auf eine Nachkommastelle.
    func testBreathingAndHeartRate() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let breathing = [reading(at(9, 1), 14), reading(at(9, 2), 15), reading(at(9, 6, 10), 20)]
        let result = try XCTUnwrap(night(main, breathing: breathing, heart: 52.44))
        XCTAssertEqual(result.respiratoryRate, 14.5)
        XCTAssertEqual(result.sleepingHeartRate, 52.4)
        XCTAssertNil(try XCTUnwrap(night(main, heart: 300)).sleepingHeartRate,
                     "was der Dienst ablehnt, fehlt lieber - sonst scheiterte die ganze Anfrage")
    }

    // MARK: - Zum Dienst

    /// Zeitpunkte als ISO 8601 mit `Z`, wie Jacksons `Instant` sie liest; was
    /// unbekannt ist, steht gar nicht erst im JSON.
    func testNightEncodesInstantsInUtcAndLeavesUnknownOut() throws {
        let main = try XCTUnwrap(mains([segment(at(8, 23), at(9, 6))], [october9]).first)
        let data = try APIClient.encoder().encode(try XCTUnwrap(night(main)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["date"] as? String, "2026-10-09")
        XCTAssertEqual(object["sleepStart"] as? String, "2026-10-08T21:00:00Z")
        XCTAssertEqual(object["sleepEnd"] as? String, "2026-10-09T04:00:00Z")
        XCTAssertEqual(object["asleepMinutes"] as? Int, 420)
        XCTAssertNil(object["hrvSdnnMs"])
        XCTAssertNil(object["inBedMinutes"])
    }
}
