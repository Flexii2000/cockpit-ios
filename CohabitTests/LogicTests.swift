import XCTest
@testable import coHabit

/// Was die App selbst entscheidet - wenig, aber das muss stimmen: die
/// Kachel nach einem eigenen Haken, Zahlen aus dem Eingabefeld, die Tage fuer
/// den Health-Abgleich, das „Weiter" im Anlegen.
final class WidgetDataTests: XCTestCase {

    func testOwnCheckInShowsAtOnce() throws {
        let data = try APIClient.decoder().decode(WidgetData.self, from: Fixtures.data(Fixtures.widget))
        let marked = data.markingDone("c-3f2a")
        XCTAssertEqual(marked.openCount, 1)
        XCTAssertEqual(marked.cohabits.first?.status, .done)
        XCTAssertEqual(marked.cohabits.first?.statusText, "erledigt")
        XCTAssertEqual(marked.cohabits.first?.quickCheckIn, false)
        XCTAssertNil(marked.openStreak, "der offene Streak ist jetzt nicht mehr offen")
        // Zweimal zaehlt nicht doppelt, ein unbekanntes Co-Habit aendert nichts.
        XCTAssertEqual(marked.markingDone("c-3f2a").openCount, 1)
        XCTAssertEqual(data.markingDone("gibt-es-nicht"), data)
    }

    func testRoundWidgetText() {
        func item(_ value: String, _ unit: String) -> WidgetData.Item {
            WidgetData.Item(ref: CohabitRef(id: "x", name: "Laufen", color: .peach, type: .streak), value: value,
                            unit: unit, sub: "", status: .open, statusText: "offen", photoRequired: false,
                            quickCheckIn: false)
        }
        XCTAssertEqual(CircularCohabitView.compact(item("6", "Wochen")), "6W")
        XCTAssertEqual(CircularCohabitView.compact(item("23", "Tage")), "23T")
        XCTAssertEqual(CircularCohabitView.compact(item("4", "Mal")), "4×")
        XCTAssertEqual(CircularCohabitView.compact(item("#2", "Platz")), "#2")
        XCTAssertEqual(CircularCohabitView.compact(item("68%", "")), "68%")
        XCTAssertEqual(ChallengeWidgetRow.score(9), "9")
        XCTAssertEqual(ChallengeWidgetRow.score(12.5), "12,5")
    }

    func testSampleIsComplete() {
        XCTAssertEqual(WidgetData.sample.cohabits.count, 4)
        XCTAssertNotNil(WidgetData.sample.challenge)
        XCTAssertEqual(WidgetData.sample.openCount, WidgetData.sample.cohabits.filter { $0.status == .open }.count)
    }
}

final class InputTests: XCTestCase {

    func testGermanNumbers() {
        XCTAssertEqual(ValueEntrySheet.number("8.200", unit: "STEPS"), 8200)
        XCTAssertEqual(ValueEntrySheet.number("8200", unit: "STEPS"), 8200)
        XCTAssertEqual(ValueEntrySheet.number("5,2", unit: "KM"), 5.2)
        XCTAssertEqual(ValueEntrySheet.number("5.2", unit: "KM"), 5.2, "bei km ist der Punkt ein Komma")
        XCTAssertEqual(ValueEntrySheet.number("1.234,5", unit: "KM"), 1234.5)
        XCTAssertEqual(ValueEntrySheet.number(" 42 ", unit: "MINUTES"), 42)
        XCTAssertNil(ValueEntrySheet.number("", unit: "COUNT"))
        XCTAssertNil(ValueEntrySheet.number("abc", unit: "COUNT"))
        XCTAssertNil(ValueEntrySheet.number("0", unit: "COUNT"), "null ist kein Eintrag")
        XCTAssertNil(ValueEntrySheet.number("-3", unit: "COUNT"))
        XCTAssertEqual(ValueEntrySheet.format(8200), "8200")
        XCTAssertEqual(ValueEntrySheet.format(5.2), "5,2")
        XCTAssertEqual(ValueEntrySheet.unitTitle("KM"), "Kilometer")
        XCTAssertEqual(ValueEntrySheet.unitTitle(nil), "Wert")
    }

    func testSettingsValidation() {
        var config = CohabitConfig.draft(.streak)
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Name fehlt")
        config.name = "   "
        XCTAssertNotNil(CohabitSettingsForm.problem(config))
        config.name = "Laufen"
        XCTAssertNil(CohabitSettingsForm.problem(config))
        config.streak?.rhythm = CohabitConfig.Rhythm(kind: "WEEKDAYS", weekdays: [])
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Wochentage fehlen")

        var goal = CohabitConfig.draft(.goal)
        goal.name = "100k"
        XCTAssertNil(CohabitSettingsForm.problem(goal))
        goal.goal?.target = 0
        XCTAssertEqual(CohabitSettingsForm.problem(goal), "Zielwert fehlt")

        var challenge = CohabitConfig.draft(.challenge)
        challenge.name = "Kochen"
        challenge.challenge?.scoring = "FIRST_TO_TARGET"
        XCTAssertEqual(CohabitSettingsForm.problem(challenge), "Zielwert fehlt")
        challenge.challenge?.target = 20
        XCTAssertNil(CohabitSettingsForm.problem(challenge))
        let start = challenge.challenge!.start
        challenge.challenge?.end = start.adding(days: -1)
        XCTAssertEqual(CohabitSettingsForm.problem(challenge), "Ende liegt vor dem Start")
    }

    func testBackfillTitles() {
        XCTAssertEqual(CohabitConfig.backfillChoices.map(CohabitSettingsForm.backfillTitle),
                       ["keine", "24 Stunden", "48 Stunden", "72 Stunden", "7 Tage", "14 Tage"])
    }

    @MainActor
    func testSyncLineText() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(SyncLine.parts(stale: nil, pending: 0), [])
        XCTAssertEqual(SyncLine.parts(stale: nil, pending: 1), ["1 Änderung wartet"])
        XCTAssertEqual(SyncLine.parts(stale: date, pending: 2).first?.hasPrefix("Offline · Stand: "), true)
        XCTAssertEqual(SyncLine.parts(stale: date, pending: 2).last, "2 Änderungen warten")
    }

    func testReactionsCountLocally() {
        let start = [ReactionView(reaction: .stark, label: "Stark", count: 2, mine: false)]
        let added = Reactions.locally(start, reaction: .stark, add: true)
        XCTAssertEqual(added.first?.count, 3)
        XCTAssertEqual(added.first?.mine, true)
        let new = Reactions.locally(start, reaction: .haha, add: true)
        XCTAssertEqual(new.last?.label, "Haha")
        let removed = Reactions.locally([ReactionView(reaction: .stark, label: "Stark", count: 1, mine: true)],
                                        reaction: .stark, add: false)
        XCTAssertTrue(removed.isEmpty)
    }
}

final class HealthDaysTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// 30.09.2026, 14:00 in Berlin.
    private var now: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 14))!
    }

    func testAlwaysTodayAndYesterday() {
        let days = CohabitHealthSync.days(backfillHours: 0, zone: berlin, now: now)
        XCTAssertEqual(days.map(\.iso), ["2026-09-30", "2026-09-29"])
    }

    func testBackfillWindow() {
        XCTAssertEqual(CohabitHealthSync.days(backfillHours: 48, zone: berlin, now: now).map(\.iso),
                       ["2026-09-30", "2026-09-29", "2026-09-28"])
        XCTAssertEqual(CohabitHealthSync.days(backfillHours: 336, zone: berlin, now: now).count, 15)
    }

    func testDaysFollowTheCohabitZone() {
        // 14:00 in Berlin ist in Auckland schon der naechste Tag.
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        XCTAssertEqual(CohabitHealthSync.days(backfillHours: 0, zone: auckland, now: now).first?.iso, "2026-10-01")
    }
}

@MainActor
final class CheckInTargetTests: XCTestCase {

    func testFromSummaryAndDetail() throws {
        let summary = try APIClient.decoder().decode(CohabitSummary.self, from: Fixtures.data(Fixtures.summary))
        let fromSummary = CheckInTarget(summary: summary, meId: "felix")
        XCTAssertEqual(fromSummary.otherMembers, ["Lena"])
        XCTAssertEqual(fromSummary.membersText, "Lena")
        XCTAssertTrue(fromSummary.photoRequired)
        XCTAssertNil(fromSummary.backfillFrom, "aus „Heute“ kein anderer Tag")

        let detail = try APIClient.decoder().decode(CohabitDetail.self, from: Fixtures.data(Fixtures.streakDetail))
        let fromDetail = CheckInTarget(detail: detail, meId: "felix")
        XCTAssertEqual(fromDetail.backfillFrom, CalendarDate(year: 2026, month: 9, day: 28))
        XCTAssertEqual(fromDetail.zone.identifier, "Europe/Berlin")
        XCTAssertEqual(fromDetail.label, "Beweisfoto & abhaken")
    }

    func testMembersText() throws {
        let detail = try APIClient.decoder().decode(CohabitDetail.self, from: Fixtures.data(Fixtures.streakDetail))
        let target = CheckInTarget(detail: detail, meId: "nobody")
        XCTAssertEqual(target.membersText, "Felix und Lena")
    }
}
