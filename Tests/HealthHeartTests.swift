import XCTest
@testable import Healthy

/// Das Puls-Histogramm je Tag (Vertrag §7.2). Die Abfrage braucht echtes
/// Health - was aus den Minutenmitteln wird, nicht. Dieselben Regeln gelten
/// auf Android (`HealthHeartTest`); weichen sie ab, rechnen die Apps
/// verschieden.
final class HealthHeartTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    /// Weit nach allen Testtagen - „jetzt“ kappt dann nichts.
    private var later: Date { time(day: 1, 0, 0, month: 12, year: 2027) }

    private func time(day: Int, _ hour: Int, _ minute: Int, second: Int = 0, month: Int = 11,
                      year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour,
                                                  minute: minute, second: second))!
    }

    private func date(_ day: Int, month: Int = 11) -> CalendarDate {
        CalendarDate(year: 2026, month: month, day: day)
    }

    private func minute(_ hour: Int, _ minute: Int, _ bpm: Double, day: Int = 9) -> HeartMinute {
        HeartMinute(start: time(day: day, hour, minute), bpm: bpm)
    }

    private func histogram(_ minutes: [HeartMinute], day: Int = 9, now: Date? = nil) -> HeartDayUpload? {
        HealthHeart.day(date(day), minutes: minutes, now: now ?? later, in: berlin)
    }

    // MARK: - Halten

    /// Aufeinanderfolgende Minuten zaehlen je eine; die letzte gilt weiter,
    /// hoechstens fuenf Minuten zusammen.
    func testConsecutiveMinutesCountOneEachAndTheLastHolds() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 62), minute(10, 1, 63), minute(10, 2, 64)]))
        XCTAssertEqual(day.fromBpm, 60)
        XCTAssertEqual(day.minutes, [7], "1 + 1 + 5")
        XCTAssertEqual(day.coverageMinutes, 7)
        XCTAssertEqual(day.date, date(9))
    }

    /// Eine Uhr in Ruhe misst nur alle paar Minuten: laenger als fuenf Minuten
    /// gilt ein Wert nicht - danach ist der Puls unbekannt.
    func testAMinuteHoldsAtMostFiveMinutes() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 62), minute(10, 20, 62)]))
        XCTAssertEqual(day.minutes, [10], "5 + 5, die 15 Minuten dazwischen fehlen")
        XCTAssertEqual(day.coverageMinutes, 10)
    }

    /// Bis zur naechsten belegten Minute - und die zaehlt dann in ihr eigenes Fach.
    func testHoldEndsAtTheNextPopulatedMinute() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 62), minute(10, 3, 101)]))
        XCTAssertEqual(day.fromBpm, 60)
        XCTAssertEqual(day.minutes, [3, 0, 0, 0, 0, 0, 0, 0, 5], "Fach 60 drei Minuten, Fach 100 fuenf")
        XCTAssertEqual(day.coverageMinutes, 8)
    }

    /// Die Reihenfolge der Abfrage spielt keine Rolle.
    func testOrderOfTheMinutesDoesNotMatter() {
        let ordered = [minute(10, 0, 62), minute(10, 3, 101), minute(10, 4, 99)]
        XCTAssertEqual(histogram(ordered.reversed()), histogram(ordered))
    }

    // MARK: - Kappen

    /// An der Mitternacht des Tages ist Schluss - was danach kommt, gehoert
    /// dem naechsten Tag, und dessen Minuten zaehlen hier nicht.
    func testHoldIsCutAtMidnight() throws {
        let minutes = [minute(23, 58, 55), minute(0, 1, 57, day: 10)]
        let first = try XCTUnwrap(histogram(minutes))
        XCTAssertEqual(first.minutes, [2], "23:58 bis Mitternacht")
        let second = try XCTUnwrap(histogram(minutes, day: 10))
        XCTAssertEqual(second.minutes, [5], "die Minute des 9. haelt nicht in den 10. hinein")
    }

    /// Heute endet der Tag jetzt: die letzte Messung gilt nur bis zu diesem
    /// Augenblick, in ganzen Sekunden.
    func testHoldIsCutAtNow() throws {
        let now = time(day: 9, 10, 2, second: 30).addingTimeInterval(0.9)
        let day = try XCTUnwrap(histogram([minute(10, 0, 62)], now: now))
        XCTAssertEqual(day.minutes, [2.5], "150 Sekunden")
        XCTAssertEqual(day.coverageMinutes, 2.5)
    }

    /// Eine Minute, die erst nach „jetzt“ beginnt, gibt es noch nicht.
    func testMinutesAfterNowDoNotCount() {
        XCTAssertNil(histogram([minute(10, 5, 62)], now: time(day: 9, 10, 2)))
    }

    /// Ein Tag, der noch nicht begonnen hat, hat kein Histogramm.
    func testADayThatHasNotBegunHasNoHistogram() {
        XCTAssertNil(histogram([minute(10, 0, 62, day: 10)], day: 10, now: time(day: 9, 22, 0)))
        XCTAssertNil(HealthHeart.dayEnd(date(10), now: time(day: 9, 22, 0), in: berlin))
        XCTAssertEqual(HealthHeart.dayEnd(date(9), now: time(day: 9, 22, 0), in: berlin), time(day: 9, 22, 0))
        XCTAssertEqual(HealthHeart.dayEnd(date(8), now: time(day: 9, 22, 0), in: berlin), time(day: 9, 0, 0))
    }

    /// Ein Rest unter drei Sekunden rundet auf 0,0 - das Fach ist dann nicht
    /// belegt, und ein Tag nur daraus fehlt.
    func testAFractionThatRoundsToZeroIsNoCoverage() {
        XCTAssertNil(histogram([minute(10, 0, 62)], now: time(day: 9, 10, 0, second: 2)))
    }

    // MARK: - Zeitumstellung

    /// Der Tag der Umstellung auf Sommerzeit hat 23 Stunden - durchgehend
    /// gemessen sind das 1.380 Minuten.
    func testTwentyThreeHourDay() throws {
        let start = time(day: 29, 0, 0, month: 3)
        let minutes = (0..<1380).map { HeartMinute(start: start.addingTimeInterval(Double($0) * 60), bpm: 61) }
        let day = try XCTUnwrap(HealthHeart.day(date(29, month: 3), minutes: minutes, now: later, in: berlin))
        XCTAssertEqual(day.coverageMinutes, 1380)
        XCTAssertEqual(day.minutes, [1380])
    }

    /// Der Tag der Umstellung auf Winterzeit hat 25 Stunden - genau so viel,
    /// wie der Dienst hoechstens annimmt.
    func testTwentyFiveHourDay() throws {
        let start = time(day: 25, 0, 0, month: 10)
        let minutes = (0..<1500).map { HeartMinute(start: start.addingTimeInterval(Double($0) * 60), bpm: 61) }
        let day = try XCTUnwrap(HealthHeart.day(date(25, month: 10), minutes: minutes, now: later, in: berlin))
        XCTAssertEqual(day.coverageMinutes, 1500)
        XCTAssertLessThanOrEqual(day.coverageMinutes, HealthHeart.maxCoverageMinutes)
        // Die letzte Minute des Tages haelt nicht in den naechsten hinein.
        let next = HealthHeart.day(date(26, month: 10), minutes: minutes, now: later, in: berlin)
        XCTAssertNil(next)
    }

    // MARK: - Faecher

    /// Fach = das Vielfache von fuenf darunter.
    func testBinEdges() {
        XCTAssertEqual(HealthHeart.bin(25), 25)
        XCTAssertEqual(HealthHeart.bin(29.99), 25)
        XCTAssertEqual(HealthHeart.bin(30), 30)
        XCTAssertEqual(HealthHeart.bin(99.9), 95)
        XCTAssertEqual(HealthHeart.bin(100), 100)
        XCTAssertEqual(HealthHeart.bin(250), 250)
    }

    /// Unter 25 oder ueber 250 gilt als nicht gemessen - die Grenzen selbst
    /// zaehlen. Von 25 bis 250 sind es 46 Faecher, mehr nimmt der Dienst nicht.
    func testImplausibleValuesAreNotMeasured() throws {
        XCTAssertNil(histogram([minute(10, 0, 24.9), minute(11, 0, 250.1)]))
        let day = try XCTUnwrap(histogram([minute(10, 0, 25), minute(11, 0, 250)]))
        XCTAssertEqual(day.fromBpm, 25)
        XCTAssertEqual(day.minutes.count, 46)
        XCTAssertEqual(day.minutes.first, 5)
        XCTAssertEqual(day.minutes.last, 5)
        XCTAssertEqual(day.coverageMinutes, 10)
    }

    /// Eine unplausible Minute ist wie keine: sie beendet das Halten der
    /// Minute davor nicht.
    func testAnImplausibleMinuteDoesNotEndTheHold() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 62), minute(10, 1, 300), minute(10, 2, 62)]))
        XCTAssertEqual(day.minutes, [7], "2 bis zur naechsten gueltigen, dann 5")
    }

    /// Der Dienst nimmt `fromBpm` nur bis 220 an und liesse sonst die ganze
    /// Anfrage scheitern: ein Tag nur aus Werten weit oben beginnt dort.
    func testFromBpmNeverExceedsWhatTheServiceAccepts() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 241)]))
        XCTAssertEqual(day.fromBpm, 220)
        XCTAssertEqual(day.minutes, [0, 0, 0, 0, 5])
        XCTAssertEqual(day.coverageMinutes, 5)
    }

    // MARK: - Mehrere Tage

    /// Eine Abfrage, mehrere Tage: jeder bekommt seine Minuten, ein Tag ohne
    /// Abdeckung fehlt - er wird nicht geschickt.
    func testDaysFromOneQuery() {
        let minutes = [minute(8, 0, 58, day: 7), minute(8, 1, 59, day: 7), minute(19, 30, 132, day: 9)]
        let days = HealthHeart.days([date(9), date(7), date(8)], minutes: minutes, now: later, in: berlin)
        XCTAssertEqual(days.map(\.date), [date(7), date(9)], "aufsteigend, der 8. fehlt")
        XCTAssertEqual(days.first?.minutes, [6])
        XCTAssertEqual(days.last?.fromBpm, 130)
    }

    // MARK: - Was zum Dienst geht

    /// Die Felder aus dem Vertrag §7.1, und `replace` fehlt - die App schickt
    /// es nie.
    func testUploadMatchesTheContract() throws {
        let day = try XCTUnwrap(histogram([minute(10, 0, 62), minute(10, 3, 71)]))
        let upload = HeartUpload(days: [day], replace: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: APIClient.encoder().encode(upload)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["days"])
        let sent = try XCTUnwrap((object["days"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(sent.keys), ["date", "coverageMinutes", "fromBpm", "minutes"])
        XCTAssertEqual(sent["date"] as? String, "2026-11-09")
        XCTAssertEqual(sent["fromBpm"] as? Int, 60)
        XCTAssertEqual(sent["minutes"] as? [Double], [3, 0, 5])
        XCTAssertEqual(sent["coverageMinutes"] as? Double, 8)
    }

    /// Nur ein geaendertes Histogramm geht noch einmal hinaus: gleiche Tage
    /// haben denselben Fingerabdruck, ein anderer Wert einen anderen.
    func testDigestFollowsTheContent() throws {
        let first = try XCTUnwrap(histogram([minute(10, 0, 62)]))
        let same = try XCTUnwrap(histogram([minute(10, 0, 62)]))
        let other = try XCTUnwrap(histogram([minute(10, 0, 62), minute(12, 0, 62)]))
        XCTAssertEqual(HealthSync.digest(first), HealthSync.digest(same))
        XCTAssertNotEqual(HealthSync.digest(first), HealthSync.digest(other))
    }
}
