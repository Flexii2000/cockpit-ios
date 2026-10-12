import XCTest
@testable import Healthy

/// Das Logbook im Dashboard ohne Oberflaeche: welcher Wert in einer Zeile steht,
/// wann ein Tag offen ist, welcher Tag vorgewaehlt ist (Vertrag §4.2). Nur
/// Platzhalter-Namen - das Repo ist oeffentlich.
final class LogbookDaysTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 10, day: 12)
    private var yesterday: CalendarDate { today.adding(days: -1) }

    private let behaviors = [
        Behavior(id: "b-1", name: "Verhalten A", unit: nil, createdAt: nil, archived: false),
        Behavior(id: "b-2", name: "Verhalten B", unit: "Tassen", createdAt: nil, archived: false),
        Behavior(id: "b-3", name: "Verhalten C", unit: nil, createdAt: nil, archived: true),
    ]

    private func overview(_ days: [CalendarDate: [String: Double]]) -> LogbookOverview {
        LogbookOverview(behaviors: behaviors, backfillDays: 14, backfillFrom: today.adding(days: -14), today: today,
                        days: days.map { LogbookDay(date: $0.key, savedAt: nil, values: $0.value) }
                            .sorted { $0.date < $1.date })
    }

    private func set(_ date: CalendarDate, _ id: String, _ value: Double?) -> LogbookChange {
        .setValue(date: date, behaviorId: id, value: value)
    }

    // MARK: - Wert einer Zeile

    /// Getippt vor wartend vor Dienst - und was fehlt, ist offen, nicht „nein“.
    func testTypedBeatsWaitingBeatsTheService() {
        let base = overview([yesterday: ["b-1": 1, "b-2": 3]])
        XCTAssertEqual(LogbookDays.value(of: "b-2", on: yesterday, overview: base, pending: []), 3)
        let pending = [set(yesterday, "b-2", 4), set(yesterday, "b-2", 5)]
        XCTAssertEqual(LogbookDays.value(of: "b-2", on: yesterday, overview: base, pending: pending), 5,
                       "der neueste wartende gilt")
        XCTAssertEqual(LogbookDays.value(of: "b-2", on: yesterday, overview: base, pending: pending,
                                         typed: [LogbookChange.key(yesterday, "b-2"): 7]), 7)
        XCTAssertNil(LogbookDays.value(of: "b-1", on: today, overview: base, pending: []), "heute offen")
    }

    /// Wartet ein Leeren, ist die Zeile offen - auch wenn der Dienst noch einen Wert hat.
    func testAWaitingClearOpensTheRow() {
        let base = overview([yesterday: ["b-1": 1]])
        XCTAssertNil(LogbookDays.value(of: "b-1", on: yesterday, overview: base, pending: [set(yesterday, "b-1", nil)]))
        let open: Double? = nil
        XCTAssertNil(LogbookDays.value(of: "b-1", on: yesterday, overview: base, pending: [],
                                       typed: [LogbookChange.key(yesterday, "b-1"): open]))
    }

    // MARK: - Offen

    /// Offen ist ein Tag, solange eine aktive Verhaltensweise keinen Wert hat -
    /// die archivierte zaehlt nicht, ein wartender Wert zaehlt.
    func testADayIsOpenUntilEveryActiveRowIsAnswered() {
        let base = overview([yesterday: ["b-1": 0]])
        XCTAssertTrue(LogbookDays.isOpen(yesterday, overview: base, pending: []))
        XCTAssertFalse(LogbookDays.isOpen(yesterday, overview: base, pending: [set(yesterday, "b-2", 0)]),
                       "0 Tassen ist eine Antwort")
        XCTAssertFalse(LogbookDays.isOpen(yesterday, overview: overview([yesterday: ["b-1": 1, "b-2": 2]]),
                                          pending: []))
    }

    func testCompleteDaysForTheReminder() {
        let base = overview([yesterday: ["b-1": 1, "b-2": 2], today.adding(days: -2): ["b-1": 1]])
        XCTAssertEqual(LogbookDays.completeDays(base, pending: []), [yesterday])
        XCTAssertEqual(LogbookDays.completeDays(base, pending: [set(today.adding(days: -2), "b-2", 0)]),
                       [yesterday, today.adding(days: -2)])
        let empty = LogbookOverview(behaviors: [], backfillDays: 14, backfillFrom: today, today: today, days: [])
        XCTAssertTrue(LogbookDays.completeDays(empty, pending: []).isEmpty, "ohne Verhalten keine Erinnerung")
    }

    // MARK: - Tag

    /// Gestern, solange gestern offen ist - sonst heute.
    func testYesterdayWhileItIsOpenThenToday() {
        XCTAssertEqual(LogbookDays.preferredDay(today: today, overview: overview([:]), pending: []), yesterday)
        let done = overview([yesterday: ["b-1": 1, "b-2": 0]])
        XCTAssertEqual(LogbookDays.preferredDay(today: today, overview: done, pending: []), today)
        XCTAssertEqual(LogbookDays.preferredDay(today: today, overview: nil, pending: []), yesterday,
                       "vor dem ersten Laden")
    }

    func testDaysStayInsideTheWindow() {
        XCTAssertEqual(LogbookDays.clamp(today.adding(days: 1), today: today, backfillDays: 14), today)
        XCTAssertEqual(LogbookDays.clamp(today.adding(days: -20), today: today, backfillDays: 14),
                       today.adding(days: -14))
        XCTAssertEqual(LogbookDays.clamp(today.adding(days: -3), today: today, backfillDays: 14),
                       today.adding(days: -3))
    }

    // MARK: - Tippen

    /// Aus „offen“ gibt + eine 1 und − eine 0; sonst eins mehr oder weniger, nie unter 0.
    func testTheCounterStartsFromOpen() {
        XCTAssertEqual(LogbookDays.stepped(nil, by: 1), 1)
        XCTAssertEqual(LogbookDays.stepped(nil, by: -1), 0)
        XCTAssertEqual(LogbookDays.stepped(3, by: 1), 4)
        XCTAssertEqual(LogbookDays.stepped(0, by: -1), 0)
        XCTAssertEqual(LogbookDays.stepped(2.5, by: -1), 1.5)
        XCTAssertEqual(LogbookDays.stepped(10_000, by: 1), 10_000, "mehr nimmt der Dienst nicht")
    }

    /// Ein zweiter Tipp auf die gewaehlte Antwort macht die Zeile wieder offen.
    func testTappingTheChosenAnswerAgainOpensTheRow() {
        XCTAssertEqual(LogbookDays.answered(nil, yes: true), 1)
        XCTAssertEqual(LogbookDays.answered(nil, yes: false), 0)
        XCTAssertNil(LogbookDays.answered(1, yes: true))
        XCTAssertNil(LogbookDays.answered(0, yes: false))
        XCTAssertEqual(LogbookDays.answered(1, yes: false), 0)
    }

    /// Der Dienst antwortet mit dem ganzen Tag; ohne Werte faellt er weg.
    func testAnAnsweredDayReplacesTheOldOne() {
        let base = overview([yesterday: ["b-1": 1]])
        let replaced = base.replacing(LogbookDay(date: yesterday, savedAt: nil, values: ["b-1": 1, "b-2": 2]))
        XCTAssertEqual(replaced.day(yesterday)?.values, ["b-1": 1, "b-2": 2])
        XCTAssertEqual(replaced.days.count, 1)
        XCTAssertNil(base.replacing(LogbookDay(date: yesterday, savedAt: nil, values: [:])).day(yesterday))
    }

    /// Der Zeitraum der Effekte bleibt - aber nur einer, den der Dienst kennt.
    func testThePeriodIsRemembered() throws {
        let suite = "LogbookPeriodTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LogbookPeriod.load(from: defaults), LogbookAPI.defaultPeriod)
        LogbookPeriod.save(365, in: defaults)
        XCTAssertEqual(LogbookPeriod.load(from: defaults), 365)
        defaults.set(42, forKey: LogbookPeriod.key)
        XCTAssertEqual(LogbookPeriod.load(from: defaults), LogbookAPI.defaultPeriod)
    }
}
