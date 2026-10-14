import XCTest
@testable import Healthy

/// Die Erinnerung um 09:00: „gestern offen", nur wenn am Vortag noch etwas
/// offen ist - je Tag eine Mitteilung, 14 Tage voraus.
final class LogbookReminderTests: XCTestCase {

    private let friday = CalendarDate(year: 2026, month: 10, day: 9)

    private func at(_ date: CalendarDate, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date.startOfDay())!
    }

    /// Vor neun und mit offenem Gestern: heute und die naechsten 13 Tage.
    func testRemindsTodayBeforeNineWhenYesterdayIsOpen() {
        let days = LogbookReminder.days(complete: [], now: at(friday, 8, 30))
        XCTAssertEqual(days.first, friday)
        XCTAssertEqual(days.count, LogbookReminder.horizonDays)
        XCTAssertEqual(days.last, friday.adding(days: 13))
    }

    /// Nach neun ist die Mitteilung von heute vorbei.
    func testNoReminderTodayAfterNine() {
        XCTAssertEqual(LogbookReminder.days(complete: [], now: at(friday, 9, 0)).first, friday.adding(days: 1))
        XCTAssertEqual(LogbookReminder.days(complete: [], now: at(friday, 9, 0)).count,
                       LogbookReminder.horizonDays - 1)
    }

    /// Gestern beantwortet: heute nichts. Ein beantworteter Tag nimmt genau
    /// die Erinnerung am Morgen danach weg.
    func testCompleteDayRemovesTheMorningAfter() {
        let days = LogbookReminder.days(complete: [friday.adding(days: -1), friday.adding(days: 1)],
                                        now: at(friday, 7, 0))
        XCTAssertFalse(days.contains(friday))
        XCTAssertFalse(days.contains(friday.adding(days: 2)))
        XCTAssertTrue(days.contains(friday.adding(days: 1)))
    }

    /// iOS haelt hoechstens 64 Mitteilungen je App. Die Evaluation (30) wohnt
    /// seit 14.10. in Fokus; der Abstand bleibt, falls hier wieder etwas dazukommt.
    func testLeavesRoomForOtherReminders() {
        XCTAssertLessThanOrEqual(LogbookReminder.horizonDays + 30, 64)
    }

    func testIdentifierAndKind() {
        XCTAssertEqual(LogbookReminder.identifier(for: friday), "logbook-2026-10-09")
        XCTAssertEqual(LogbookReminder.kind, "logbook")
        XCTAssertEqual(HealthyRoute.notification(kind: LogbookReminder.kind), .logbook)
    }
}
