import XCTest
@testable import coHabit

/// Die klassische Liste: die Antwort von `/classic/habits`, so wie sie
/// wirklich aussieht - die alten `HabitsModelTests` der Fokus-App sinngemaess,
/// dazu die vier Felder aus coHabit, `WINDOWS`, ein Rhythmus ohne `period` und
/// Werte, die es heute noch nicht gibt.
final class ClassicModelTests: XCTestCase {

    private func decode(_ json: String) throws -> [ClassicHabit] {
        try APIClient.decoder().decode([ClassicHabit].self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Das Beispiel aus der Beschreibung der Endpunkte, Feld fuer Feld.
    static let contract = """
    [{"id":"c-1a2b","name":"Lesen","kind":"BUILD","unit":"DAYS","weeklyStepGoal":null,"focusMinutesGoal":null,
      "period":"DAY","timesPerPeriod":null,"streak":11,"doneToday":false,"atRisk":true,
      "progress":{"value":1,"goal":2},"recent":[false,true,true,true,true,true,false],"unavailable":null,
      "markedDays":["2026-09-28","2026-09-29"],"createdAt":"2026-08-01",
      "photoRequired":false,"shared":false,"admin":true,"backfillFrom":"2026-09-16"}]
    """

    /// Die alte Antwort ohne die vier neuen Felder - so sah `/habits/api/habits` aus.
    static let oldShape = """
    [{"id":"s1","name":"70.000 Schritte / Woche","kind":"STEPS","unit":"WEEKS",
      "weeklyStepGoal":70000,"streak":3,"doneToday":false,"atRisk":false,
      "progress":{"value":55432,"goal":70000},
      "recent":[true,true,true,true,true,true,false],"unavailable":null},
     {"id":"b1","name":"Logbook","kind":"BUILD","unit":"DAYS","weeklyStepGoal":null,
      "streak":12,"doneToday":false,"atRisk":true,"progress":null,
      "recent":[true,true,true,true,true,true,false],"unavailable":null},
     {"id":"f1","name":"Track food","kind":"FOOD","unit":"DAYS","weeklyStepGoal":null,
      "streak":0,"doneToday":false,"atRisk":false,"progress":null,
      "recent":[],"unavailable":"Kalorienzähler nicht erreichbar"}]
    """

    func testDecodesTheContractShape() throws {
        let habit = try XCTUnwrap(try decode(Self.contract).first)
        XCTAssertEqual(habit.id, "c-1a2b")
        XCTAssertEqual(habit.name, "Lesen")
        XCTAssertEqual(habit.kind, .build)
        XCTAssertEqual(habit.unit, .days)
        XCTAssertNil(habit.weeklyStepGoal)
        XCTAssertNil(habit.focusMinutesGoal)
        XCTAssertEqual(habit.period, .day)
        XCTAssertNil(habit.timesPerPeriod)
        XCTAssertEqual(habit.streak, 11)
        XCTAssertFalse(habit.doneToday)
        XCTAssertTrue(habit.atRisk)
        XCTAssertEqual(habit.progress, ClassicProgress(value: 1, goal: 2))
        XCTAssertEqual(habit.recent, [false, true, true, true, true, true, false])
        XCTAssertNil(habit.unavailable)
        XCTAssertEqual(habit.markedDays, [CalendarDate(year: 2026, month: 9, day: 28),
                                          CalendarDate(year: 2026, month: 9, day: 29)])
        XCTAssertEqual(habit.createdAt, CalendarDate(year: 2026, month: 8, day: 1))
        XCTAssertFalse(habit.photoRequired)
        XCTAssertFalse(habit.shared)
        XCTAssertTrue(habit.admin)
        XCTAssertEqual(habit.backfillFrom, CalendarDate(year: 2026, month: 9, day: 16))
        XCTAssertEqual(habit.streakText, "11 Tage")
        XCTAssertEqual(habit.openText, "heute noch offen")
        XCTAssertTrue(habit.hasClassicRhythm)
    }

    /// Ein Dienst ohne die neuen Felder laesst die Liste weiter laden - allein,
    /// kein Admin, keine Foto-Pflicht.
    func testDecodesTheOldServerShape() throws {
        let habits = try decode(Self.oldShape)
        XCTAssertEqual(habits.count, 3)
        XCTAssertEqual(habits[0].kind, .steps)
        XCTAssertEqual(habits[0].unit, .weeks)
        XCTAssertEqual(habits[0].progress?.stepsText, "55/70k")
        XCTAssertTrue(habits[1].atRisk)
        XCTAssertEqual(habits[1].streakText, "12 Tage")
        XCTAssertEqual(habits[2].unavailable, "Kalorienzähler nicht erreichbar")
        XCTAssertEqual(habits[1].markedDays, [])
        XCTAssertNil(habits[1].createdAt)
        XCTAssertFalse(habits[1].isMarked(.today()))
        XCTAssertFalse(habits[1].photoRequired || habits[1].shared || habits[1].admin)
    }

    func testStepsTextRoundsToThousandsAndKeepsOvershoot() {
        XCTAssertEqual(ClassicProgress(value: 98_400, goal: 70_000).stepsText, "98/70k")
        XCTAssertEqual(ClassicProgress(value: 499, goal: 70_000).stepsText, "0/70k")
        XCTAssertEqual(ClassicProgress(value: 500, goal: 70_000).stepsText, "1/70k")
        // Kein runder Tausender: dann die vollen Zahlen, sonst wuerde 75.500 zu "75k".
        XCTAssertEqual(ClassicProgress(value: 1_000, goal: 75_500).stepsText, "1.000/75.500")
    }

    func testFractionIsCappedAtOne() {
        XCTAssertEqual(ClassicProgress(value: 98_400, goal: 70_000).fraction, 1)
        XCTAssertEqual(ClassicProgress(value: 35_000, goal: 70_000).fraction, 0.5)
        XCTAssertEqual(ClassicProgress(value: 10, goal: 0).fraction, 0)
    }

    func testKcalText() {
        XCTAssertEqual(ClassicProgress(value: 1_470, goal: 1_840).kcalText, "1.470/1.840 kcal")
    }

    /// Fokus-Zeit mit Tagesziel in Minuten, Stand als „h:mm".
    func testDecodesFocusHabitAndFormatsHours() throws {
        let habit = try decode("""
        [{"id":"x1","name":"Fokus","kind":"FOCUS","unit":"DAYS","weeklyStepGoal":null,
          "streak":2,"doneToday":false,"atRisk":true,"progress":{"value":135,"goal":240},
          "recent":[false,false,false,false,true,true,false],"unavailable":null,
          "focusMinutesGoal":240}]
        """)[0]
        XCTAssertEqual(habit.kind, .focus)
        XCTAssertTrue(habit.kind.isAutomatic)
        XCTAssertFalse(habit.canBackfill)
        XCTAssertEqual(habit.focusMinutesGoal, 240)
        XCTAssertEqual(habit.progress?.focusText, "2:15/4:00 h")
        XCTAssertEqual(ClassicProgress.hours(0), "0:00")
        XCTAssertEqual(ClassicProgress.hours(605), "10:05")
    }

    func testDecodesMarkedDaysAndCreatedAt() throws {
        let habits = try decode("""
        [{"id":"b1","name":"Logbook","kind":"BUILD","unit":"DAYS","weeklyStepGoal":null,
          "streak":2,"doneToday":true,"atRisk":false,"progress":null,
          "recent":[false,false,false,false,false,true,true],"unavailable":null,
          "markedDays":["2026-09-22","2026-09-23"],"createdAt":"2026-09-01"}]
        """)
        XCTAssertTrue(habits[0].isMarked(CalendarDate(year: 2026, month: 9, day: 22)))
        XCTAssertFalse(habits[0].isMarked(CalendarDate(year: 2026, month: 9, day: 21)))
        XCTAssertEqual(habits[0].createdAt, CalendarDate(year: 2026, month: 9, day: 1))
    }

    /// Selbst abgehakte zuerst, automatische danach, sonst nichts umsortiert.
    func testManualHabitsComeBeforeAutomaticOnes() throws {
        let habits = try decode(Self.oldShape)
        XCTAssertEqual(habits.classicOrder.map(\.id), ["b1", "s1", "f1"])
    }

    /// Ein Habit je Woche oder Monat: Rhythmus, Einheit und der Stand des
    /// Zeitraums.
    func testDecodesPeriodicBuildHabit() throws {
        let habits = try decode("""
        [{"id":"w1","name":"Zeitungsartikel lesen","kind":"BUILD","unit":"WEEKS","weeklyStepGoal":null,
          "streak":3,"doneToday":false,"atRisk":true,"progress":{"value":0,"goal":1},
          "recent":[true,true,true,true,true,true,false],"unavailable":null,
          "focusMinutesGoal":null,"period":"WEEK","timesPerPeriod":1},
         {"id":"m1","name":"Politisch aktiv","kind":"BUILD","unit":"MONTHS","weeklyStepGoal":null,
          "streak":1,"doneToday":true,"atRisk":false,"progress":{"value":2,"goal":2},
          "recent":[false,false,false,false,false,true,true],"unavailable":null,
          "focusMinutesGoal":null,"period":"MONTH","timesPerPeriod":2}]
        """)
        XCTAssertEqual(habits[0].rhythm, .week)
        XCTAssertTrue(habits[0].isPeriodic)
        XCTAssertEqual(habits[0].streakText, "3 Wochen")
        XCTAssertEqual(habits[0].openText, "diese Woche noch offen")
        XCTAssertEqual(habits[1].rhythm, .month)
        XCTAssertEqual(habits[1].streakText, "1 Monat")
        XCTAssertEqual(habits[1].openText, "diesen Monat noch offen")
        XCTAssertEqual(habits[1].timesPerPeriod, 2)
    }

    func testStreakTextHandlesSingular() throws {
        let one = try decode("""
        [{"id":"q","name":"x","kind":"QUIT","unit":"DAYS","weeklyStepGoal":null,"streak":1,
          "doneToday":true,"atRisk":false,"progress":null,"recent":[true],"unavailable":null}]
        """)[0]
        XCTAssertEqual(one.streakText, "1 Tag")
        XCTAssertFalse(one.kind.isAutomatic)
        XCTAssertTrue(one.canBackfill)
    }

    /// „alle n Tage": „1 Mal", „4 Mal", „noch offen" - und kein Rhythmus, den
    /// das alte Formular zeigen koennte.
    func testWindowsUnitAndARhythmTheOldFormDoesNotKnow() throws {
        let habits = try decode("""
        [{"id":"i1","name":"Pflanzen giessen","kind":"BUILD","unit":"WINDOWS","weeklyStepGoal":null,
          "focusMinutesGoal":null,"period":null,"timesPerPeriod":null,"streak":1,"doneToday":false,
          "atRisk":true,"progress":null,"recent":[true,true,false,true,true,true,false],"unavailable":null,
          "markedDays":[],"createdAt":"2026-09-01","photoRequired":false,"shared":true,"admin":true,
          "backfillFrom":"2026-09-28"},
         {"id":"i2","name":"Pflanzen giessen","kind":"BUILD","unit":"WINDOWS","weeklyStepGoal":null,
          "focusMinutesGoal":null,"period":null,"timesPerPeriod":null,"streak":4,"doneToday":true,
          "atRisk":false,"progress":null,"recent":[],"unavailable":null,"markedDays":[],
          "createdAt":"2026-09-01","photoRequired":false,"shared":false,"admin":false,"backfillFrom":null}]
        """)
        XCTAssertEqual(habits[0].unit, .windows)
        XCTAssertEqual(habits[0].streakText, "1 Mal")
        XCTAssertEqual(habits[1].streakText, "4 Mal")
        XCTAssertEqual(habits[0].openText, "noch offen")
        XCTAssertNil(habits[0].period)
        XCTAssertFalse(habits[0].hasClassicRhythm, "das Formular blendet den Rhythmus aus")
        XCTAssertFalse(habits[0].isPeriodic)
        XCTAssertTrue(habits[0].shared)
    }

    /// Eine Art, eine Einheit, ein Rhythmus, die es heute noch nicht gibt: die
    /// Liste laedt trotzdem, die Zeile hat nichts zum Antippen.
    func testUnknownValuesDoNotBreakTheList() throws {
        let habits = try decode("""
        [{"id":"u1","name":"Neu","kind":"MEDITATE","unit":"YEARS","weeklyStepGoal":null,
          "period":"FORTNIGHT","timesPerPeriod":2,"streak":2,"doneToday":false,"atRisk":false,
          "progress":null,"recent":[true,false],"unavailable":null,"markedDays":["kein Datum"],
          "createdAt":"irgendwann","photoRequired":false,"shared":false,"admin":true,"backfillFrom":null},
         {"id":"b1","name":"Logbook","kind":"BUILD","unit":"DAYS","weeklyStepGoal":null,
          "streak":12,"doneToday":false,"atRisk":true,"progress":null,
          "recent":[true,true,true,true,true,true,false],"unavailable":null}]
        """)
        XCTAssertEqual(habits.count, 2)
        XCTAssertEqual(habits[0].kind, .unknown)
        XCTAssertTrue(habits[0].kind.isAutomatic)
        XCTAssertFalse(habits[0].canBackfill)
        XCTAssertEqual(habits[0].unit, .windows)
        XCTAssertEqual(habits[0].streakText, "2 Mal")
        XCTAssertNil(habits[0].period)
        XCTAssertEqual(habits[0].markedDays, [])
        XCTAssertNil(habits[0].createdAt)
        XCTAssertEqual(habits.classicOrder.map(\.id), ["b1", "u1"])
        XCTAssertFalse(ClassicHabit.Kind.creatable.contains(.unknown))
    }

    /// Foto-Pflicht haelt nur das Abhaken auf - einen Rueckfall traegt man ohne
    /// Foto ein, und nachtragen per Langdruck gibt es mit Foto-Pflicht nicht.
    func testPhotoRequiredOnlyBlocksTicking() throws {
        let habits = try decode("""
        [{"id":"p1","name":"Laufen","kind":"BUILD","unit":"WEEKS","streak":1,"doneToday":false,"atRisk":true,
          "recent":[],"period":"WEEK","timesPerPeriod":3,"photoRequired":true,"shared":true,"admin":false},
         {"id":"p2","name":"Ohne Zucker","kind":"QUIT","unit":"DAYS","streak":1,"doneToday":true,"atRisk":false,
          "recent":[],"photoRequired":true}]
        """)
        XCTAssertTrue(habits[0].needsPhoto)
        XCTAssertFalse(habits[0].canBackfill)
        XCTAssertFalse(habits[1].needsPhoto)
        XCTAssertTrue(habits[1].canBackfill)
    }

    /// Die letzten 14 Tage - aber nicht vor dem Start und nicht vor dem
    /// fruehesten Tag, den der Dienst noch annimmt; beide Grenzen gelten.
    func testBackfillDaysStopAtTheStartAndAtBackfillFrom() throws {
        let today = CalendarDate(year: 2026, month: 9, day: 30)
        func habit(createdAt: String?, backfillFrom: String?) throws -> ClassicHabit {
            func field(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
            return try decode("""
            [{"id":"b1","name":"Logbook","kind":"BUILD","unit":"DAYS","streak":1,"doneToday":false,
              "atRisk":true,"recent":[],"createdAt":\(field(createdAt)),"backfillFrom":\(field(backfillFrom))}]
            """)[0]
        }
        let all = try habit(createdAt: nil, backfillFrom: nil).backfillDays(today: today)
        XCTAssertEqual(all.count, 14)
        XCTAssertEqual(all.first, today)
        XCTAssertEqual(all.last, CalendarDate(year: 2026, month: 9, day: 17))

        let young = try habit(createdAt: "2026-09-27", backfillFrom: "2026-09-16").backfillDays(today: today)
        XCTAssertEqual(young.last, CalendarDate(year: 2026, month: 9, day: 27))
        XCTAssertEqual(young.count, 4)

        let strict = try habit(createdAt: "2026-08-01", backfillFrom: "2026-09-28").backfillDays(today: today)
        XCTAssertEqual(strict, [today, CalendarDate(year: 2026, month: 9, day: 29),
                                CalendarDate(year: 2026, month: 9, day: 28)])

        let monthChange = try habit(createdAt: nil, backfillFrom: nil)
            .backfillDays(today: CalendarDate(year: 2026, month: 10, day: 2))
        XCTAssertEqual(monthChange[2], CalendarDate(year: 2026, month: 9, day: 30))
    }

    // MARK: - Was die App schickt

    /// Alle Schluessel, leere als `null` - wie ueberall in coHabit.
    func testDraftEncodesEveryKey() throws {
        let weekly = try object(ClassicHabitDraft(name: "Lesen", kind: .build, period: .week, timesPerPeriod: 1))
        XCTAssertEqual(weekly["name"] as? String, "Lesen")
        XCTAssertEqual(weekly["kind"] as? String, "BUILD")
        XCTAssertEqual(weekly["period"] as? String, "WEEK")
        XCTAssertEqual(weekly["timesPerPeriod"] as? Int, 1)
        XCTAssertTrue(weekly["weeklyStepGoal"] is NSNull)
        XCTAssertTrue(weekly["focusMinutesGoal"] is NSNull)

        let steps = try object(ClassicHabitDraft(name: "Schritte", kind: .steps, weeklyStepGoal: 70_000))
        XCTAssertEqual(steps["weeklyStepGoal"] as? Int, 70_000)
        XCTAssertTrue(steps["period"] is NSNull)
    }

    /// Das Formular: Ziele nur bei ihrer Art, die Haeufigkeit nur bei Woche und
    /// Monat - und ein Rhythmus, den es nicht zeigt, geht als `null` raus,
    /// damit der Dienst ihn stehen laesst.
    func testDraftFromTheForm() {
        let daily = ClassicHabitDraft(form: "Logbook", kind: .build, stepGoal: 70_000, focusMinutes: 240,
                                      period: .day, timesPerPeriod: 3)
        XCTAssertEqual(daily, ClassicHabitDraft(name: "Logbook", kind: .build, period: .day))

        let monthly = ClassicHabitDraft(form: "Politisch aktiv", kind: .build, stepGoal: nil, focusMinutes: nil,
                                        period: .month, timesPerPeriod: 2)
        XCTAssertEqual(monthly.period, .month)
        XCTAssertEqual(monthly.timesPerPeriod, 2)

        let unknownRhythm = ClassicHabitDraft(form: "Pflanzen", kind: .build, stepGoal: nil, focusMinutes: nil,
                                              period: nil, timesPerPeriod: 1)
        XCTAssertNil(unknownRhythm.period)
        XCTAssertNil(unknownRhythm.timesPerPeriod)

        let focus = ClassicHabitDraft(form: "Fokus", kind: .focus, stepGoal: 70_000, focusMinutes: 240,
                                      period: .week, timesPerPeriod: 2)
        XCTAssertEqual(focus, ClassicHabitDraft(name: "Fokus", kind: .focus, focusMinutesGoal: 240))
    }

    /// Die Kennung passt in das, was der Dienst annimmt (8-64 Zeichen aus
    /// `[A-Za-z0-9-]`), und jeder Haken bekommt seine eigene.
    func testMarkRequestCarriesAClientId() throws {
        let day = CalendarDate(year: 2026, month: 9, day: 30)
        let request = ClassicMarkRequest(date: day)
        XCTAssertNotNil(request.id.range(of: "^[A-Za-z0-9-]{8,64}$", options: .regularExpression))
        XCTAssertNotEqual(request.id, ClassicMarkRequest(date: day).id)
        let body = try object(request)
        XCTAssertEqual(body["date"] as? String, "2026-09-30")
        XCTAssertEqual(body["id"] as? String, request.id)
        XCTAssertEqual(ClassicMarkRequest.path(habitId: "c-1"), "/classic/habits/c-1/marks")
        XCTAssertEqual(ClassicMarkRequest.path(habitId: "c-1", date: day), "/classic/habits/c-1/marks/2026-09-30")
    }
}

/// Ziele und Challenges in der klassischen Liste (seit 2026-10-01): die alten
/// Felder neutral, dazu `summary` wie in `GET /cohabits`.
final class ClassicGoalChallengeTests: XCTestCase {

    static func summaryJSON(id: String, name: String, type: String, headline: String, listLine: String,
                            progress: String, canCheckIn: Bool = true, photoRequired: Bool = false,
                            valueUnit: String = "null", label: String) -> String {
        """
        {"ref":{"id":"\(id)","name":"\(name)","color":"periwinkle","type":"\(type)"},"archived":false,
         "headline":{"value":"\(headline)","unit":"","short":"\(headline)"},"typeLine":"\(type)",
         "subline":"Teamziel · 4 machen mit","listLine":"\(listLine)","status":"RUNNING","section":"RUNNING",
         "unavailableText":null,"canCheckIn":\(canCheckIn),"photoRequired":\(photoRequired),"valueUnit":\(valueUnit),
         "checkInLabel":"\(label)","members":[\(Fixtures.felix)],"memberCount":4,"doneTodayBy":[],
         "progress":\(progress),"rank":null,"unreadMessages":0}
        """
    }

    static func habitJSON(id: String, kind: String, summary: String = "null", doneToday: Bool = true) -> String {
        """
        {"id":"\(id)","name":"Habit \(id)","kind":"\(kind)","unit":"DAYS","weeklyStepGoal":null,"streak":0,
         "doneToday":\(doneToday),"atRisk":false,"progress":null,"recent":[],"unavailable":null,
         "focusMinutesGoal":null,"period":null,"timesPerPeriod":null,"markedDays":[],"createdAt":"2026-09-16",
         "photoRequired":false,"shared":true,"admin":true,"backfillFrom":"2026-09-28","summary":\(summary)}
        """
    }

    static let goal = summaryJSON(id: "c-goal", name: "1 Mio. Schritte", type: "GOAL", headline: "30%",
                                  listLine: "308.700 von 1.000.000 · noch 31 Tage",
                                  progress: #"{"done":308700,"goal":1000000,"fraction":0.31}"#,
                                  valueUnit: #""STEPS""#, label: "Schritte manuell eintragen")
    static let challenge = summaryJSON(id: "c-chal", name: "Wer kocht öfter?", type: "CHALLENGE", headline: "#1",
                                       listLine: "Challenge · endet in 30 Tagen · gleichauf mit Torben",
                                       progress: "null", label: "+1 Wer kocht öfter? eintragen")

    private func decode(_ items: [String]) throws -> [ClassicHabit] {
        try APIClient.decoder().decode([ClassicHabit].self, from: Fixtures.data("[" + items.joined(separator: ",") + "]"))
    }

    func testDecodesGoalsAndChallengesWithTheirSummary() throws {
        let habits = try decode([Self.habitJSON(id: "c-goal", kind: "GOAL", summary: Self.goal),
                                 Self.habitJSON(id: "c-chal", kind: "CHALLENGE", summary: Self.challenge)])
        XCTAssertEqual(habits[0].kind, .goal)
        XCTAssertEqual(habits[0].summary?.headline.value, "30%")
        XCTAssertEqual(habits[0].summary?.listLine, "308.700 von 1.000.000 · noch 31 Tage")
        XCTAssertEqual(habits[0].summary?.progress?.fraction, 0.31)
        XCTAssertEqual(habits[0].summary?.valueUnit, "STEPS")
        XCTAssertEqual(habits[1].kind, .challenge)
        XCTAssertEqual(habits[1].summary?.headline.value, "#1")
        XCTAssertNil(habits[1].summary?.progress, "Challenges haben keinen Stand, nur einen Platz")
        XCTAssertTrue(habits[1].kind.usesSummary)
        XCTAssertFalse(habits[1].kind.isAutomatic)
        XCTAssertFalse(habits[1].kind.takesMarks)
    }

    /// Erst Aufbauen und Lassen, dann Ziele und Challenges, dann die
    /// automatischen - innerhalb der Gruppen die Anlegereihenfolge.
    func testOrderManualThenGoalsAndChallengesThenAutomatic() throws {
        let habits = try decode([
            Self.habitJSON(id: "f1", kind: "FOOD"),
            Self.habitJSON(id: "g1", kind: "GOAL", summary: Self.goal),
            Self.habitJSON(id: "b1", kind: "BUILD"),
            Self.habitJSON(id: "c1", kind: "CHALLENGE", summary: Self.challenge),
            Self.habitJSON(id: "q1", kind: "QUIT"),
            Self.habitJSON(id: "s1", kind: "STEPS"),
            Self.habitJSON(id: "b2", kind: "BUILD"),
        ])
        XCTAssertEqual(habits.classicOrder.map(\.id), ["b1", "q1", "b2", "g1", "c1", "f1", "s1"])
    }

    /// Welcher Knopf was ausloest.
    func testWhichActionTheButtonTriggers() throws {
        let photo = Self.habitJSON(id: "p1", kind: "BUILD", doneToday: false)
            .replacingOccurrences(of: #""photoRequired":false"#, with: #""photoRequired":true"#)
        let habits = try decode([
            Self.habitJSON(id: "b1", kind: "BUILD", doneToday: false),
            photo,
            Self.habitJSON(id: "q1", kind: "QUIT"),
            Self.habitJSON(id: "g1", kind: "GOAL", summary: Self.goal),
            Self.habitJSON(id: "c1", kind: "CHALLENGE",
                           summary: Self.challenge.replacingOccurrences(of: #""canCheckIn":true"#,
                                                                       with: #""canCheckIn":false"#)),
            Self.habitJSON(id: "f1", kind: "FOOD"),
            Self.habitJSON(id: "u1", kind: "MEDITATE"),
        ])
        XCTAssertEqual(habits.map(\.action), [.mark, .proofPhoto, .mark, .checkIn, .none, .none, .none])
    }

    /// Eintragen bei Ziel und Challenge laeuft ueber `CheckInController` wie in
    /// der neuen Liste: Wert-Blatt mit `valueUnit`, Beweisfoto bei Foto-Pflicht,
    /// sonst gleich +1.
    func testCheckInFollowsTheNewList() throws {
        let photoGoal = Self.goal.replacingOccurrences(of: #""photoRequired":false"#, with: #""photoRequired":true"#)
        let habits = try decode([
            Self.habitJSON(id: "c-goal", kind: "GOAL", summary: Self.goal),
            Self.habitJSON(id: "c-chal", kind: "CHALLENGE", summary: Self.challenge),
            Self.habitJSON(id: "c-goal", kind: "GOAL", summary: photoGoal),
        ])
        let summaries = try habits.map { try XCTUnwrap($0.summary) }
        let steps = summaries.map { CheckInController.step(for: CheckInTarget(summary: $0, meId: "felix")) }
        XCTAssertEqual(steps, [.value, .submit, .photo])
        XCTAssertEqual(CheckInTarget(summary: summaries[1], meId: "felix").label, "+1 Wer kocht öfter? eintragen")
    }

    /// Ziele und Challenges: Tipp auf den Namen immer zur Detailseite, kein
    /// Nachtragen per Langdruck, und der Editor legt weiter nur die alten fuenf an.
    func testGoalsAndChallengesOpenTheDetailAndAreNotCreatable() throws {
        let habits = try decode([Self.habitJSON(id: "g1", kind: "GOAL", summary: Self.goal),
                                 Self.habitJSON(id: "b1", kind: "BUILD")])
        XCTAssertFalse(habits[0].opensEditor, "auch als Admin")
        XCTAssertTrue(habits[1].opensEditor)
        XCTAssertFalse(habits[0].canBackfill)
        XCTAssertEqual(ClassicHabit.Kind.creatable, [.build, .quit, .food, .steps, .focus])
    }
}

/// Die Liste gegen einen Dienst im Speicher: welche Anfrage bei welchem Tipp
/// rausgeht, was ohne Netz im Postausgang landet, welche Meldung stehen bleibt.
@MainActor
final class ClassicStoreTests: XCTestCase {

    private var directory: URL!
    private var outbox: CohabitOutbox!
    private var events: [ClassicStore.Event] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "classic-\(UUID().uuidString)")
        outbox = CohabitOutbox(directory: directory)
        events = []
        CohabitSync.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        CohabitSync.shared.reset()
    }

    /// Heute so, wie die Liste es rechnet - fuer diese Kennungen ist keine
    /// Zone gemerkt, also Europe/Berlin.
    private var today: CalendarDate { .today(in: CheckInTarget.defaultZone) }

    /// Wie `StubServer.api()`, aber ohne den geteilten Postausgang der App
    /// anzustossen - dessen Reste aus einem Simulator-Lauf gehoerten nicht in
    /// diese Anfragen.
    nonisolated static func stubAPI() -> CohabitAPI {
        CohabitAPI(token: "test-token", baseURL: URL(string: "https://stub.test/cohabit/api")!,
                   timeout: 5, session: StubServer.session(), usesCache: false, replaysOutbox: false)
    }

    private func makeStore() -> ClassicStore {
        ClassicStore(makeAPI: { ClassicStoreTests.stubAPI() }, outbox: outbox,
                     publish: { [weak self] event in self?.events.append(event) })
    }

    private func habitJSON(id: String, kind: String = "BUILD", doneToday: Bool = false, streak: Int = 3,
                           shared: Bool = false) -> String {
        """
        {"id":"\(id)","name":"Habit \(id)","kind":"\(kind)","unit":"DAYS","weeklyStepGoal":null,
         "focusMinutesGoal":null,"period":\(kind == "BUILD" ? "\"DAY\"" : "null"),"timesPerPeriod":null,
         "streak":\(streak),"doneToday":\(doneToday),"atRisk":false,"progress":null,
         "recent":[true,true,true,true,true,true,\(doneToday)],"unavailable":null,"markedDays":[],
         "createdAt":"2026-09-01","photoRequired":false,"shared":\(shared),"admin":true,
         "backfillFrom":"2026-09-16"}
        """
    }

    private func loadedStore(_ list: [String]) async -> ClassicStore {
        let body = "[" + list.joined(separator: ",") + "]"
        StubServer.install { _ in .json(200, body) }
        let store = makeStore()
        await store.load()
        return store
    }

    func testLoadAsksForTheClassicListAndSortsManualFirst() async throws {
        let store = await loadedStore([habitJSON(id: "f1", kind: "FOOD"), habitJSON(id: "b1")])
        XCTAssertEqual(StubServer.requests.map(\.path), ["/cohabit/api/classic/habits"])
        XCTAssertEqual(StubServer.requests.first?.headers["Authorization"], "Bearer test-token")
        XCTAssertEqual(store.habits.map(\.id), ["b1", "f1"])
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(events, [.loaded])
    }

    /// Der Haken schickt heute mit ausdruecklichem Datum und eigener Kennung;
    /// die Antwort ersetzt die Zeile, die Kachel erfaehrt es.
    func testTickingABuildHabitSendsTodayWithAClientId() async throws {
        let store = await loadedStore([habitJSON(id: "b1")])
        let done = habitJSON(id: "b1", doneToday: true, streak: 4)
        StubServer.install { _ in .json(200, done) }
        await store.toggleToday(store.habits[0])

        let request = try XCTUnwrap(StubServer.requests.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/cohabit/api/classic/habits/b1/marks")
        XCTAssertEqual(request.json?["date"] as? String, today.iso)
        XCTAssertEqual((request.json?["id"] as? String)?.count, 36)
        XCTAssertTrue(store.habits[0].doneToday)
        XCTAssertEqual(store.habits[0].streak, 4)
        XCTAssertEqual(events.last, .markedToday("b1"))

        // Noch einmal getippt: der Haken geht wieder weg.
        let open = habitJSON(id: "b1", streak: 3)
        StubServer.install { _ in .json(200, open) }
        await store.toggleToday(store.habits[0])
        XCTAssertEqual(StubServer.requests.last?.method, "DELETE")
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits/b1/marks/\(today.iso)")
        XCTAssertFalse(store.habits[0].doneToday)
        XCTAssertEqual(events.last, .updated("b1"))
    }

    /// Lassen: „erledigt" heisst kein Rueckfall - der Knopf traegt einen ein
    /// oder nimmt ihn zurueck.
    func testQuitRecordsARelapseAndTakesItBack() async throws {
        let store = await loadedStore([habitJSON(id: "q1", kind: "QUIT", doneToday: true)])
        let relapsed = habitJSON(id: "q1", kind: "QUIT", doneToday: false, streak: 0)
        StubServer.install { _ in .json(200, relapsed) }
        await store.toggleToday(store.habits[0])
        XCTAssertEqual(StubServer.requests.last?.method, "POST")
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits/q1/marks")
        XCTAssertEqual(events.last, .updated("q1"), "ein Rueckfall ist kein „heute erledigt\" fuer die Kachel")

        let clean = habitJSON(id: "q1", kind: "QUIT", doneToday: true)
        StubServer.install { _ in .json(200, clean) }
        await store.toggleToday(store.habits[0])
        XCTAssertEqual(StubServer.requests.last?.method, "DELETE")
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits/q1/marks/\(today.iso)")
        XCTAssertTrue(store.habits[0].doneToday)
    }

    /// Automatische Habits hakt man nicht ab - da geht nichts raus.
    func testAutomaticHabitsSendNothing() async {
        let store = await loadedStore([habitJSON(id: "f1", kind: "FOOD")])
        let before = StubServer.requests.count
        await store.toggleToday(store.habits[0])
        await store.setMarked(store.habits[0], day: today, marked: true)
        XCTAssertEqual(StubServer.requests.count, before)
    }

    /// Ziele und Challenges nehmen keine Haken - eingetragen wird ueber das
    /// Co-Habit, nicht ueber `…/marks`.
    func testGoalsAndChallengesSendNoMarks() async {
        let store = await loadedStore([
            ClassicGoalChallengeTests.habitJSON(id: "g1", kind: "GOAL", summary: ClassicGoalChallengeTests.goal),
        ])
        let before = StubServer.requests.count
        await store.setMarked(store.habits[0], day: today, marked: true)
        XCTAssertEqual(StubServer.requests.count, before)
        XCTAssertEqual(store.habits[0].action, .checkIn)
    }

    /// Ohne Netz: Haken und Ruecknahme warten im Postausgang - mit derselben
    /// Kennung, die beim Nachsenden rausgeht. Ein 409 dort heisst „steht schon".
    func testWithoutNetworkTheTickWaitsInTheOutbox() async throws {
        let store = await loadedStore([habitJSON(id: "b1"), habitJSON(id: "q1", kind: "QUIT")])
        StubServer.install { _ in .offline }
        await store.toggleToday(store.habits[0])
        await store.toggleToday(store.habits[1])
        XCTAssertNil(store.errorMessage, "kein Fehler - es wartet nur")
        XCTAssertEqual(CohabitSync.shared.pendingClassic, ["b1", "q1"], "die Zeilen zeigen eine Uhr")
        XCTAssertEqual(events.last, .queuedToday("b1"))

        let entries = await outbox.entries()
        XCTAssertEqual(entries.count, 2)
        guard case .classicMark(let habitId, let request) = entries.first?.operation else {
            return XCTFail("kein Haken im Postausgang")
        }
        XCTAssertEqual(habitId, "b1")
        XCTAssertEqual(request.date, today)
        guard case .classicUnmark("q1", today) = entries.last?.operation else {
            return XCTFail("keine Ruecknahme des Rueckfalls im Postausgang")
        }

        StubServer.install { request in
            request.method == "POST" ? .json(409, #"{"message":"Heute schon erledigt."}"#) : .json(200, "{}")
        }
        await outbox.replay(using: ClassicStoreTests.stubAPI())
        let sent = StubServer.requests
        XCTAssertEqual(sent.map(\.method), ["POST", "DELETE"])
        XCTAssertEqual(sent[0].json?["id"] as? String, request.id, "dieselbe Kennung wie beim ersten Versuch")
        XCTAssertEqual(sent[1].path, "/cohabit/api/classic/habits/q1/marks/\(today.iso)")
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        XCTAssertNil(CohabitSync.shared.lastError)
        XCTAssertEqual(CohabitSync.shared.pendingClassic, [])
    }

    /// Nachtragen per Langdruck: ein frueherer Tag, dasselbe Endpunktpaar.
    func testBackfillingAnEarlierDay() async throws {
        let store = await loadedStore([habitJSON(id: "b1")])
        let yesterday = today.adding(days: -1)
        let answer = habitJSON(id: "b1")
        StubServer.install { _ in .json(200, answer) }
        await store.setMarked(store.habits[0], day: yesterday, marked: true)
        XCTAssertEqual(StubServer.requests.last?.json?["date"] as? String, yesterday.iso)
        XCTAssertEqual(events.last, .updated("b1"), "nicht heute - die Kachel rechnet der Dienst")
    }

    /// Loeschen: 204, die Zeile ist weg. Lehnt der Dienst ab, steht seine
    /// Meldung da; ohne Netz auch - Loeschen wartet nicht im Postausgang.
    func testDeleteAndTheServicesMessages() async throws {
        let store = await loadedStore([habitJSON(id: "b1"), habitJSON(id: "b2", shared: true)])
        StubServer.install { _ in .json(204, "") }
        await store.delete(store.habits[1])
        XCTAssertEqual(StubServer.requests.last?.method, "DELETE")
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits/b2")
        XCTAssertEqual(store.habits.map(\.id), ["b1"])
        XCTAssertEqual(events.last, .removed("b2"))

        StubServer.install { _ in .json(403, #"{"message":"Nur der Admin darf das."}"#) }
        await store.setMarked(store.habits[0], day: today, marked: true)
        XCTAssertEqual(store.errorMessage, "Nur der Admin darf das.")

        StubServer.install { _ in .offline }
        await store.delete(store.habits[0])
        XCTAssertEqual(store.errorMessage, "Kein Netz.")
        XCTAssertEqual(store.habits.count, 1)
        let waiting = await outbox.entries()
        XCTAssertTrue(waiting.isEmpty)
    }

    /// Anlegen: der Rumpf des alten Formulars; lehnt der Dienst ab, bekommt
    /// das Blatt seine Meldung und die Liste bleibt, wie sie war.
    func testCreateSendsTheDraftOrHandsBackTheRejection() async throws {
        let store = await loadedStore([habitJSON(id: "b1")])
        StubServer.install { _ in .json(403, #"{"message":"Diese Quelle hast du nicht."}"#) }
        let rejection = await store.create(ClassicHabitDraft(name: "Fokus", kind: .focus, focusMinutesGoal: 240))
        XCTAssertEqual(rejection, "Diese Quelle hast du nicht.")
        XCTAssertEqual(store.habits.count, 1)
        let body = try XCTUnwrap(StubServer.requests.last?.json)
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits")
        XCTAssertEqual(body["kind"] as? String, "FOCUS")
        XCTAssertEqual(body["focusMinutesGoal"] as? Int, 240)

        let created = habitJSON(id: "q9", kind: "QUIT")
        StubServer.install { _ in .json(201, created) }
        let accepted = await store.create(ClassicHabitDraft(name: "Ohne", kind: .quit))
        XCTAssertNil(accepted)
        XCTAssertEqual(store.habits.map(\.id), ["b1", "q9"])
        XCTAssertEqual(events.last, .updated("q9"))
    }

    /// Bearbeiten: `PUT` mit dem Rumpf, die Antwort ersetzt die Zeile.
    func testUpdateReplacesTheRow() async throws {
        let store = await loadedStore([habitJSON(id: "b1"), habitJSON(id: "b2")])
        let renamed = habitJSON(id: "b2").replacingOccurrences(of: "Habit b2", with: "Lesen")
        StubServer.install { _ in .json(200, renamed) }
        let rejection = await store.update(store.habits[1], ClassicHabitDraft(name: "Lesen", kind: .build))
        XCTAssertNil(rejection)
        XCTAssertEqual(StubServer.requests.last?.method, "PUT")
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/classic/habits/b2")
        XCTAssertTrue(StubServer.requests.last?.json?["period"] is NSNull)
        XCTAssertEqual(store.habits.map(\.name), ["Habit b1", "Lesen"])
    }
}

/// Der Postausgang mit Auftraegen der klassischen Liste: der Reihe nach, eine
/// Ablehnung fliegt mit Grund raus, und die Datei liest auch ein zweiter
/// Prozess (die Kachel) wieder ein.
@MainActor
final class ClassicOutboxTests: XCTestCase {

    private var directory: URL!
    private var outbox: CohabitOutbox!
    private let day = CalendarDate(year: 2026, month: 9, day: 30)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        outbox = CohabitOutbox(directory: directory)
        CohabitSync.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        CohabitSync.shared.reset()
    }

    func testClassicEntriesSurviveARestartNextToACheckin() async {
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day), photo: nil)
        await outbox.enqueueClassicMark(habitId: "c2", request: ClassicMarkRequest(date: day, id: "m-1234567"))
        await outbox.enqueueClassicUnmark(habitId: "c3", date: day)
        // Ein zweiter Leser derselben Datei - so sieht sie die Kachel.
        let again = CohabitOutbox(directory: directory)
        let entries = await again.entries()
        XCTAssertEqual(entries.count, 3, "keiner der Auftraege darf die Datei unlesbar machen")
        guard case .classicMark("c2", let request) = entries[1].operation else {
            return XCTFail("falsche Art")
        }
        XCTAssertEqual(request.id, "m-1234567")
        XCTAssertEqual(CohabitSync.shared.pendingCheckins, ["c1"])
        XCTAssertEqual(CohabitSync.shared.pendingClassic, ["c2", "c3"])
    }

    func testRejectedMarksAreDroppedWithTheReason() async {
        StubServer.install { _ in .json(400, #"{"message":"Außerhalb der Nachtragsfrist."}"#) }
        await outbox.enqueueClassicMark(habitId: "c2", request: ClassicMarkRequest(date: day))
        await outbox.replay(using: ClassicStoreTests.stubAPI())
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(CohabitSync.shared.lastError, "Nicht angenommen: Außerhalb der Nachtragsfrist.")
    }

    func testAConflictOnATakeBackIsReported() async {
        // Ein 409 ist nur beim Eintragen „steht schon" - eine Ruecknahme
        // kennt keinen Konflikt, der das Ziel waere.
        StubServer.install { _ in .json(409, #"{"message":"Konflikt."}"#) }
        await outbox.enqueueClassicUnmark(habitId: "c3", date: day)
        await outbox.replay(using: ClassicStoreTests.stubAPI())
        XCTAssertEqual(CohabitSync.shared.lastError, "Nicht angenommen: Konflikt.")
    }
}
