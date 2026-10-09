import XCTest
@testable import Healthy

/// Energie-Tage aus Tageskuebeln und die Bloecke der Rueckholung. Die
/// Abfragen selbst brauchen echtes Health - was daraus wird, nicht.
final class HealthEnergyTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func dayStart(_ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func date(_ day: Int) -> CalendarDate { CalendarDate(year: 2026, month: 10, day: day) }

    /// Ein Tag mit nur einem der beiden Werte geht trotzdem hinaus - das
    /// fehlende Feld laesst beim Dienst den gespeicherten Wert stehen.
    func testMergesActiveAndBasalPerDay() {
        let days = HealthEnergy.days(
            active: [DaySum(dayStart: dayStart(6), value: 512.04), DaySum(dayStart: dayStart(7), value: 300)],
            basal: [DaySum(dayStart: dayStart(7), value: 1834.26), DaySum(dayStart: dayStart(8), value: 1700)],
            in: berlin)
        XCTAssertEqual(days, [
            EnergyDayUpload(date: date(6), activeKcal: 512.0, basalKcal: nil),
            EnergyDayUpload(date: date(7), activeKcal: 300, basalKcal: 1834.3),
            EnergyDayUpload(date: date(8), activeKcal: nil, basalKcal: 1700),
        ])
    }

    func testWithoutAnyValueThereIsNoDay() {
        XCTAssertTrue(HealthEnergy.days(active: [], basal: [], in: berlin).isEmpty)
    }

    /// Was zum Dienst geht: fehlende Felder fehlen, `replace` auch.
    func testUploadLeavesUnknownFieldsOut() throws {
        let upload = EnergyUpload(days: [EnergyDayUpload(date: date(8), activeKcal: 512, basalKcal: nil)],
                                  replace: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: APIClient.encoder().encode(upload)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["days"])
        let day = try XCTUnwrap((object["days"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(day.keys), ["date", "activeKcal"])
        XCTAssertEqual(day["date"] as? String, "2026-10-08")
        XCTAssertEqual(day["activeKcal"] as? Double, 512)
    }

    // MARK: - Rueckholung

    /// Zehn Jahre in Jahresbloecken: neueste zuerst, ohne Luecke und ohne
    /// Ueberlappung.
    func testBackfillBlocksAreContiguousWithoutOverlap() {
        let newest = date(8)
        let oldest = newest.adding(days: -3649)
        let blocks = HealthBackfill.windows(newest: newest, oldest: oldest, blockDays: 365)
        XCTAssertEqual(blocks.count, 10)
        XCTAssertEqual(blocks.first?.to, newest)
        XCTAssertEqual(blocks.last?.from, oldest)
        for (earlier, later) in zip(blocks.dropFirst(), blocks) {
            XCTAssertEqual(earlier.to.adding(days: 1), later.from)
        }
        for block in blocks {
            XCTAssertEqual(HealthSync.days(in: block).count, 365)
        }
    }

    func testLastBlockIsShorterWhenItDoesNotDivide() {
        let blocks = HealthBackfill.windows(newest: date(8), oldest: date(8).adding(days: -399), blockDays: 365)
        XCTAssertEqual(blocks.map { HealthSync.days(in: $0).count }, [365, 35])
        XCTAssertTrue(HealthBackfill.windows(newest: date(1), oldest: date(2), blockDays: 60).isEmpty)
    }

    /// Der Cursor ist der aelteste schon geschickte Tag; der naechste Block
    /// schliesst direkt daran an, und am Ende gibt es keinen mehr.
    func testNextBlockContinuesBehindTheCursor() throws {
        let start = date(8).adding(days: -14)
        let oldest = date(8).adding(days: -365)
        let first = try XCTUnwrap(HealthBackfill.next(after: nil, start: start, oldest: oldest, blockDays: 60))
        XCTAssertEqual(first.to, start)
        XCTAssertEqual(HealthSync.days(in: first).count, 60)
        let second = try XCTUnwrap(HealthBackfill.next(after: first.from, start: start, oldest: oldest, blockDays: 60))
        XCTAssertEqual(second.to, first.from.adding(days: -1))
        XCTAssertNil(HealthBackfill.next(after: oldest, start: start, oldest: oldest, blockDays: 60))
    }

    func testWindowOfTheLastFourteenNights() {
        let days = HealthSync.days(endingAt: date(9), count: 14)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first, date(9).adding(days: -13))
        XCTAssertEqual(days.last, date(9))
    }

    // MARK: - Groesse der Anfrage

    /// nginx nimmt bei `/api/nights` hoechstens 1 MB an; eine 413 ist eine
    /// HTML-Seite, kein JSON. 200 Naechte mit allen Feldern muessen darunter
    /// bleiben - mit viel Luft.
    func testTwoHundredNightsStayWellBelowOneMegabyte() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let nights = (0..<RecoveryAPI.nightsPerRequest).map { offset in
            Night(date: date(9).adding(days: -offset),
                  sleepStart: start.addingTimeInterval(Double(-offset) * 86_400),
                  sleepEnd: start.addingTimeInterval(Double(-offset) * 86_400 + 27_000),
                  asleepMinutes: 431, inBedMinutes: 470, awakeMinutes: 24, deepMinutes: 62,
                  remMinutes: 101, coreMinutes: 268, hrvSdnnMs: 48.3, hrvSdnnSamples: 4,
                  hrvRmssdMs: 39.9, hrvRmssdSamples: 6, sleepingHeartRate: 52.4,
                  respiratoryRate: 14.2, source: "ios")
        }
        let data = try APIClient.encoder().encode(NightsUpload(nights: nights))
        XCTAssertLessThan(data.count, 1_000_000)
        XCTAssertLessThan(data.count, 100_000, "eine Nacht sind gut 400 Byte")
    }
}
