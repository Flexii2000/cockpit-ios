import XCTest
@testable import Healthy

/// Der Evaluation-Tab rechnet selbst (kein Dienst dahinter) - deshalb hier die
/// Regeln: Antworten, Mittel, Raster, Erinnerung, Frist der Sperre, Datei.
/// Mit Platzhaltern statt echter Fragen: das Repo ist oeffentlich.
final class EvaluationTests: XCTestCase {

    private let a = EvaluationQuestion(text: "Frage A")
    private let b = EvaluationQuestion(text: "Frage B")
    private let monday = CalendarDate(year: 2026, month: 9, day: 28)

    private func data(_ answers: [(CalendarDate, EvaluationQuestion, Int)]) -> EvaluationData {
        var data = EvaluationData(questions: [a, b])
        for (date, question, value) in answers { data.set(value, for: question.id, on: date) }
        return data
    }

    // MARK: - Antworten

    func testSetAndClearAnAnswer() {
        var data = data([(monday, a, 7)])
        XCTAssertEqual(data.value(of: a.id, on: monday), 7)
        data.set(nil, for: a.id, on: monday)
        XCTAssertNil(data.value(of: a.id, on: monday))
        XCTAssertTrue(data.days.isEmpty, "ein Tag ohne Antwort verschwindet ganz")
    }

    func testDaysStaySortedWhateverTheOrderOfAnswering() {
        let data = data([(monday.adding(days: 2), a, 5), (monday, a, 6), (monday.adding(days: 1), a, 4)])
        XCTAssertEqual(data.days.map(\.date), [monday, monday.adding(days: 1), monday.adding(days: 2)])
    }

    func testCompleteOnlyWithEveryQuestionAnswered() {
        XCTAssertFalse(data([(monday, a, 7)]).isComplete(on: monday))
        XCTAssertTrue(data([(monday, a, 7), (monday, b, 3)]).isComplete(on: monday))
        XCTAssertFalse(EvaluationData().isComplete(on: monday), "ohne Fragen nie vollstaendig")
    }

    func testOnlyTodayAndYesterdayAreEditable() {
        XCTAssertEqual(EvaluationDays.editable(today: monday), [monday, monday.adding(days: -1)])
    }

    @MainActor
    func testStoreRefusesOlderDaysAndTogglesTheSameValueOff() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("evaluation.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = EvaluationStore(file: file, asksForReminders: false)
        store.load()
        store.replaceQuestions([a])
        store.toggle(8, for: a.id, on: monday.adding(days: -2), today: monday)
        XCTAssertNil(store.value(of: a.id, on: monday.adding(days: -2)), "vorgestern ist nicht mehr zu setzen")
        store.toggle(8, for: a.id, on: monday.adding(days: -1), today: monday)
        XCTAssertEqual(store.value(of: a.id, on: monday.adding(days: -1)), 8)
        store.toggle(8, for: a.id, on: monday.adding(days: -1), today: monday)
        XCTAssertNil(store.value(of: a.id, on: monday.adding(days: -1)), "derselbe Wert nimmt zurueck")
    }

    // MARK: - Datei

    @MainActor
    func testStoreWritesAndReadsBack() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("evaluation.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = EvaluationStore(file: file, asksForReminders: false)
        store.load()
        store.replaceQuestions([a, EvaluationQuestion(text: "   "), b])
        let today = CalendarDate.today()
        store.toggle(9, for: b.id, on: today)

        let reread = try XCTUnwrap(EvaluationStore.read(file))
        XCTAssertEqual(reread.questions, [a, b], "leere Fragen fallen weg")
        XCTAssertEqual(reread.value(of: b.id, on: today), 9)
    }

    @MainActor
    func testUnreadableFileIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("evaluation.json")
        try Data("kein json".utf8).write(to: file)

        let store = EvaluationStore(file: file, asksForReminders: false)
        store.load()
        XCTAssertNotNil(store.error)
        store.replaceQuestions([a])
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "kein json")
    }

    func testFilesFromBeforeShortLabelsStillLoad() throws {
        let json = Data("""
        {"version":1,"questions":[{"id":"\(a.id.uuidString)","text":"Frage A"}],
         "days":[{"date":"2026-09-28","values":{"\(a.id.uuidString)":6}}]}
        """.utf8)
        let data = try JSONDecoder().decode(EvaluationData.self, from: json)
        XCTAssertNil(data.questions[0].shortLabel)
        XCTAssertEqual(data.questions[0].label, "Frage A", "ohne Kurznamen die Frage selbst")
        XCTAssertEqual(data.value(of: a.id, on: monday), 6)
    }

    @MainActor
    func testShortLabelIsTrimmedAndEmptyMeansNone() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("evaluation.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = EvaluationStore(file: file, asksForReminders: false)
        store.load()
        store.replaceQuestions([EvaluationQuestion(id: a.id, text: "Frage A", shortLabel: "  Kurz A "),
                                EvaluationQuestion(id: b.id, text: "Frage B", shortLabel: "   ")])
        let reread = try XCTUnwrap(EvaluationStore.read(file))
        XCTAssertEqual(reread.questions.map(\.shortLabel), ["Kurz A", nil])
        XCTAssertEqual(reread.questions.map(\.label), ["Kurz A", "Frage B"])
    }

    func testRemovedQuestionKeepsItsAnswersInTheFile() {
        var data = data([(monday, a, 7), (monday, b, 2)])
        data.questions = [b]
        XCTAssertEqual(data.value(of: a.id, on: monday), 7)
    }

    // MARK: - Verlauf

    func testTrailingMeanLooksSevenDaysBackOverAnsweredDaysOnly() {
        let data = data([(monday, a, 2), (monday.adding(days: 1), a, 4), (monday.adding(days: 3), a, 6),
                         (monday.adding(days: 12), a, 10)])
        let mean = EvaluationChartData.trailingMean(data, question: a.id,
                                                    from: monday, to: monday.adding(days: 12))
        let byDate = Dictionary(uniqueKeysWithValues: mean.map { ($0.date, $0.value) })
        XCTAssertEqual(byDate[monday], 2)
        XCTAssertEqual(byDate[monday.adding(days: 3)], 4, "(2 + 4 + 6) / 3")
        XCTAssertEqual(byDate[monday.adding(days: 6)], 4, "Montag liegt noch im Fenster")
        XCTAssertEqual(byDate[monday.adding(days: 7)], 5, "Montag faellt heraus: (4 + 6) / 2")
        XCTAssertEqual(byDate[monday.adding(days: 9)], 6, "Tag 3 liegt noch im Fenster")
        XCTAssertNil(byDate[monday.adding(days: 10)], "sieben Tage ohne Antwort: keine Linie")
        XCTAssertEqual(byDate[monday.adding(days: 12)], 10)
    }

    func testMeanRunsBreakAtGaps() {
        let points = [0, 1, 2, 5, 6].map { EvaluationChartData.Point(date: monday.adding(days: $0), value: 5) }
        XCTAssertEqual(EvaluationChartView.runs(points).map(\.count), [3, 2])
    }

    func testHeatmapWeeksStartOnMondayAndPadOutsideTheRange() {
        let wednesday = monday.adding(days: 2)
        let weeks = EvaluationChartData.weeks(from: wednesday, to: wednesday.adding(days: 7))
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0][0], nil, "Montag vor dem Zeitraum")
        XCTAssertEqual(weeks[0][2], wednesday)
        XCTAssertEqual(weeks[1][2], wednesday.adding(days: 7))
        XCTAssertNil(weeks[1][3], "Donnerstag nach dem Zeitraum")
        XCTAssertEqual(EvaluationChartData.weekdayIndex(of: monday), 0)
        XCTAssertEqual(EvaluationChartData.weekdayIndex(of: monday.adding(days: 6)), 6)
    }

    func testRangesInPickerOrder() {
        XCTAssertEqual(EvaluationRange.allCases.map(\.title), ["14 Tage", "30 Tage", "90 Tage", "180 Tage", "1 Jahr"])
        XCTAssertEqual(EvaluationChartData.start(of: .month, today: monday), monday.adding(days: -29))
    }

    // MARK: - Erinnerung

    private func at(_ date: CalendarDate, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date.startOfDay())!
    }

    func testReminderStartsTodayBeforeHalfPastNine() {
        let days = EvaluationReminder.days(for: data([]), now: at(monday, 20, 0))
        XCTAssertEqual(days.first, monday)
        XCTAssertEqual(days.count, EvaluationReminder.horizonDays)
    }

    func testNoReminderTodayOnceAnsweredOrLate() {
        XCTAssertEqual(EvaluationReminder.days(for: data([(monday, a, 5), (monday, b, 5)]),
                                               now: at(monday, 20, 0)).first,
                       monday.adding(days: 1))
        XCTAssertEqual(EvaluationReminder.days(for: data([]), now: at(monday, 21, 30)).first,
                       monday.adding(days: 1))
        XCTAssertEqual(EvaluationReminder.days(for: data([(monday, a, 5)]), now: at(monday, 20, 0)).first,
                       monday, "halb beantwortet erinnert trotzdem")
    }

    func testNoReminderWithoutQuestions() {
        XCTAssertTrue(EvaluationReminder.days(for: EvaluationData(), now: at(monday, 8, 0)).isEmpty)
    }

    // MARK: - Sperre

    /// Eine Uhr, die nur weitergeht, wenn der Test sie stellt.
    @MainActor
    private final class TestClock {
        let start = ContinuousClock.now
        var elapsed: Duration = .zero
        var now: ContinuousClock.Instant { start + elapsed }
    }

    @MainActor
    func testGraceCountsFromTheFirstSwitchAway() {
        let clock = TestClock()
        let lock = EvaluationLock(now: { clock.now })
        lock.leave()
        clock.elapsed = .seconds(60)
        lock.leave()  // aus dem anderen Tab heraus die App verlassen
        clock.elapsed = .seconds(299)
        XCTAssertFalse(lock.back(), "4:59 nach dem ersten Wechsel: noch offen")

        lock.leave()
        clock.elapsed = .seconds(299 + 300)
        XCTAssertTrue(lock.back(), "5:00 nach dem Verlassen: zu")
        XCTAssertNil(lock.leftAt)
    }

    @MainActor
    func testReturningWithoutLeavingNeverLocks() {
        let clock = TestClock()
        let lock = EvaluationLock(now: { clock.now })
        clock.elapsed = .seconds(3600)
        XCTAssertFalse(lock.back(), "wer den Tab nie verlassen hat, bleibt drin")
    }
}
