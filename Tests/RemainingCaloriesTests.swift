import XCTest
@testable import Cockpit

/// Die Rechnerei hinter der Kachel. Sie liegt neben der View, weil sie sonst
/// nicht zu pruefen waere - und weil hier der Unterschied zwischen einer alten
/// und einer falschen Zahl entschieden wird.
final class RemainingCaloriesTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func day(_ datum: String, consumed: Double, target: Double) -> DaySummary {
        let json = """
        {"date":"\(datum)",
         "targets":{"kcal":\(target),"proteinG":200,"carbsG":236,"fatG":62},
         "consumed":{"kcal":\(consumed),"proteinG":28,"carbsG":23,"fatG":4},
         "remaining":{"kcal":\(target - consumed),"proteinG":172,"carbsG":213,"fatG":58},
         "entries":[],"mealTargets":{}}
        """
        return try! APIClient.decoder().decode(DaySummary.self, from: Data(json.utf8))
    }

    private func zeitpunkt(_ tag: Int, _ stunde: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: tag,
                                                  hour: stunde, minute: minute))!
    }

    func testTakesTheRemainderFromTheServer() {
        let value = RemainingCalories(day: day("2026-09-02", consumed: 244, target: 2300))
        XCTAssertEqual(value.remaining.kcal, 2056)
        XCTAssertFalse(value.isOver)
    }

    func testKnowsWhenTheDayIsOverspent() {
        let value = RemainingCalories(day: day("2026-09-02", consumed: 2500, target: 2300))
        XCTAssertTrue(value.isOver)
        XCTAssertEqual(value.remaining.kcal, -200)
    }

    /// Wie im Essen-Tab: der Bogen reicht bis zum 1,25-fachen des Ziels, damit
    /// die Zielkerbe nicht am Bogenende sitzt.
    func testRatioLeavesRoomAboveTheTarget() {
        let value = RemainingCalories(day: day("2026-09-02", consumed: 2300, target: 2300))
        XCTAssertEqual(value.ratio, 0.8, accuracy: 0.0001)
    }

    func testRatioIsZeroWithoutATarget() {
        XCTAssertEqual(RemainingCalories(day: day("2026-09-02", consumed: 500, target: 0)).ratio, 0)
    }

    /// Um Mitternacht springt „uebrig" auf das volle Tagesziel zurueck. Ein
    /// Rest von gestern ist deshalb keine alte Wahrheit, sondern eine falsche
    /// Aussage ueber heute - und muss als solche erkennbar sein.
    func testYesterdaysValueIsStale() {
        let gestern = RemainingCalories(day: day("2026-09-01", consumed: 244, target: 2300))
        XCTAssertTrue(gestern.isStale(today: CalendarDate(year: 2026, month: 9, day: 2)))

        let heute = RemainingCalories(day: day("2026-09-02", consumed: 244, target: 2300))
        XCTAssertFalse(heute.isStale(today: CalendarDate(year: 2026, month: 9, day: 2)))
    }

    func testRefreshesEveryHalfHourDuringTheDay() {
        let mittags = zeitpunkt(2, 12, 0)
        XCTAssertEqual(RemainingCalories.nextRefresh(after: mittags, in: berlin),
                       zeitpunkt(2, 12, 30))
    }

    /// Kurz vor Mitternacht gewinnt der Tageswechsel: sonst stuende der Rest
    /// von gestern bis halb eins als heutiger da.
    func testMidnightWinsWhenItIsCloser() {
        let kurzVorZwoelf = zeitpunkt(2, 23, 50)
        XCTAssertEqual(RemainingCalories.nextRefresh(after: kurzVorZwoelf, in: berlin),
                       zeitpunkt(3, 0, 1))
    }
}
