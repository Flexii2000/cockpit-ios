import XCTest
@testable import Healthy

/// Die Erinnerung um 09:00: „gestern offen", nur wenn der Vortag nicht
/// gespeichert ist - je Tag eine Mitteilung, 14 Tage voraus.
final class LogbookReminderTests: XCTestCase {

    private let friday = CalendarDate(year: 2026, month: 10, day: 9)

    private func at(_ date: CalendarDate, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date.startOfDay())!
    }

    /// Vor neun und mit offenem Gestern: heute und die naechsten 13 Tage.
    func testRemindsTodayBeforeNineWhenYesterdayIsOpen() {
        let days = LogbookReminder.days(saved: [], now: at(friday, 8, 30))
        XCTAssertEqual(days.first, friday)
        XCTAssertEqual(days.count, LogbookReminder.horizonDays)
        XCTAssertEqual(days.last, friday.adding(days: 13))
    }

    /// Nach neun ist die Mitteilung von heute vorbei.
    func testNoReminderTodayAfterNine() {
        XCTAssertEqual(LogbookReminder.days(saved: [], now: at(friday, 9, 0)).first, friday.adding(days: 1))
        XCTAssertEqual(LogbookReminder.days(saved: [], now: at(friday, 9, 0)).count,
                       LogbookReminder.horizonDays - 1)
    }

    /// Gestern gespeichert: heute nichts. Ein gespeicherter Tag nimmt genau
    /// die Erinnerung am Morgen danach weg.
    func testSavedDayRemovesTheMorningAfter() {
        let days = LogbookReminder.days(saved: [friday.adding(days: -1), friday.adding(days: 1)],
                                        now: at(friday, 7, 0))
        XCTAssertFalse(days.contains(friday))
        XCTAssertFalse(days.contains(friday.adding(days: 2)))
        XCTAssertTrue(days.contains(friday.adding(days: 1)))
    }

    /// iOS haelt hoechstens 64 Mitteilungen je App; die Evaluation belegt 30.
    func testLeavesRoomForTheEvaluation() {
        XCTAssertLessThanOrEqual(LogbookReminder.horizonDays + EvaluationReminder.horizonDays, 64)
    }

    func testIdentifierAndKind() {
        XCTAssertEqual(LogbookReminder.identifier(for: friday), "logbook-2026-10-09")
        XCTAssertEqual(LogbookReminder.kind, "logbook")
        XCTAssertEqual(HealthyRoute.notification(kind: LogbookReminder.kind), .logbook)
    }

    // MARK: - Postausgang

    /// Ein Tag im Postausgang zaehlt als gespeichert - mit seinen Werten, damit
    /// die Seite ihn mit Uhr statt leer zeigt.
    func testQueuedDaysAreRememberedWithTheirValues() throws {
        let suite = "LogbookMemoryTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        XCTAssertTrue(LogbookMemory.load(from: defaults).isEmpty)
        LogbookMemory.remember(friday, values: ["b-1": 1, "b-2": 2.5], in: defaults)
        LogbookMemory.remember(friday.adding(days: -1), values: [:], in: defaults)
        let memory = LogbookMemory.load(from: defaults)
        XCTAssertEqual(memory[friday], ["b-1": 1, "b-2": 2.5])
        XCTAssertEqual(memory[friday.adding(days: -1)], [:], "ein Tag mit lauter nein wartet auch")
        LogbookMemory.clear(in: defaults)
        XCTAssertTrue(LogbookMemory.load(from: defaults).isEmpty)
    }
}
