import XCTest
@testable import Sport

/// Der Padel-Tab (23.10.): liest, was der Dienst schickt (Views.java), und beschriftet es wie
/// die Seite (`app.js`). Platzhalter statt echter Personen - das Repo ist oeffentlich.
final class PadelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_761_210_000) // Do 23.10.2025 ~11 Uhr

    private func occurrence(_ id: String, date: String = "2026-11-06", start: String = "18:00",
                            status: String = "PLANNED", note: String? = nil, club: String = "mitte",
                            fallback: Bool = false, partner: String? = "Person B",
                            release: TimeInterval = 3600) throws -> PadelOccurrence {
        let json = """
        {"id":"\(id)","oneOff":false,"moved":false,"date":"\(date)","weekday":"Fr","start":"\(start)","end":"19:30",
         "durationMinutes":90,"status":"\(status)","note":\(note.map { "\"\($0)\"" } ?? "null"),
         "releaseAt":"\(iso(now.addingTimeInterval(release)))","watchUntil":"\(iso(now.addingTimeInterval(86_400)))",
         "canSkip":true,"canUnskip":false,"canMove":false,"canRemove":false,"canRetry":false,"attempts":[],
         "club":"\(club)","fallback":\(fallback),"partner":\(partner.map { "\"\($0)\"" } ?? "null")}
        """
        return try APIClient.decoder().decode(PadelOccurrence.self, from: Data(json.utf8))
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    func testTheDemoReadsLikeTheService() {
        let overview = PadelDemo.overview(now: now)
        XCTAssertTrue(overview.viewer.owner)
        XCTAssertEqual(overview.partners?.first?.color, "#EAB308")
        XCTAssertEqual(overview.results?.first?.summary, "6:0 6:2")
        XCTAssertEqual(overview.series?.first?.firstDate?.count, 10)
        XCTAssertEqual(PadelDemo.bookings(now: now).count, 2)
        XCTAssertEqual(PadelDemo.costs().months.first?.label, "September 2026")
    }

    func testCostsReadLikeTheService() throws {
        // So schickt der Dienst es am 28.10. (Views.CostView): Betraege als Zahlen.
        let json = """
        {"month":"2026-10","label":"Oktober 2026","spent":80.38,"matches":6,"booked":15.00,"bookedMatches":1,
         "planned":0.00,"plannedDays":0,"forecast":95.38,
         "months":[{"month":"2026-09","label":"September 2026","amount":210.01,"matches":13}]}
        """
        let costs = try APIClient.decoder().decode(PadelCosts.self, from: Data(json.utf8))
        XCTAssertEqual(PadelFormat.euro(costs.spent), "80,38 €")
        XCTAssertEqual(PadelFormat.euro(costs.months[0].amount), "210,01 €")
        XCTAssertEqual(PadelFormat.forecastDetail(costs), "gebucht 15,00 € (1 Match)")
        XCTAssertEqual(PadelFormat.forecastDetail(PadelDemo.costs()),
                       "gebucht 15,00 € (1 Match) · geplant 33,00 € (2 Tage)")
        // Ein Dienst von vor dem Folgemonat schickt `next` nicht.
        XCTAssertNil(costs.next)
        let next = try XCTUnwrap(PadelDemo.costs().next)
        XCTAssertEqual(next.label, "November 2026")
        XCTAssertEqual(PadelFormat.euro(next.forecast), "255,49 €")
        XCTAssertEqual(PadelFormat.forecastDetail(next), "gebucht 84,02 € (5 Matches) · geplant 171,47 € (11 Tage)")
    }

    func testFieldsAddedLaterMayBeMissing() throws {
        // Ein Dienst von vor dem 23.10. kennt Mitspieler, Farben und Ergebnisse nicht.
        let json = """
        {"viewer":{"name":"person-a","owner":false},"now":"2026-10-23T12:00:00.123456Z","dryRun":false,"next":null,
         "occurrences":[],"feedUrl":"webcal://fherrmann.com/padel/calendar/x.ics"}
        """
        let overview = try APIClient.decoder().decode(PadelOverview.self, from: Data(json.utf8))
        XCTAssertFalse(overview.viewer.owner)
        XCTAssertNil(overview.partners)
        XCTAssertNil(overview.results)
        XCTAssertNil(overview.series)
    }

    func testPlannedHasOneEntryPerDayAndPartner() throws {
        let entries = [
            try occurrence("a", partner: "Person A"),
            try occurrence("b", club: "Padelon", partner: "Person A"),
            try occurrence("c", start: "21:30", partner: "Person B"),
            try occurrence("d", date: "2026-11-09", partner: "Person B"),
        ]

        let days = PadelPlan.days(entries, now: now)

        XCTAssertEqual(days.map(\.id), ["2026-11-06|Person A", "2026-11-06|Person B", "2026-11-09|Person B"])
        XCTAssertEqual(days[0].occurrences.map(\.id), ["a", "b"])
        XCTAssertTrue(days[1].isSingle)
    }

    func testDaysWithNothingLeftDropOut() throws {
        let done = try occurrence("x", status: "MISSED")
        let skippedByService = try occurrence("y", status: "SKIPPED", note: "an dem Tag schon gebucht")
        let skippedByPerson = try occurrence("z", date: "2026-11-09", status: "SKIPPED", note: "ausgesetzt von felix")

        let days = PadelPlan.days([done, skippedByService, skippedByPerson], now: now)

        XCTAssertEqual(days.map(\.date), ["2026-11-09"], "nur, was jemand ausgesetzt hat, bleibt sichtbar")
    }

    func testTheSummaryNamesTheClubsOnlyWhenTheyDiffer() throws {
        let same = PadelDay(date: "2026-11-06", weekday: "Fr", partner: nil, partnerColor: nil, occurrences: [
            try occurrence("a"), try occurrence("b", club: "Padelon"),
        ])
        XCTAssertTrue(PadelPlan.summary(same).hasPrefix("Freigabe "))
        XCTAssertFalse(PadelPlan.summary(same).contains("Padelon"))

        let differ = PadelDay(date: "2026-11-06", weekday: "Fr", partner: nil, partnerColor: nil, occurrences: [
            try occurrence("a", status: "BOOKED"), try occurrence("b", status: "WATCHING", club: "Padelon"),
            try occurrence("c", club: "Aspria", fallback: true, release: 7200),
        ])
        let summary = PadelPlan.summary(differ)
        XCTAssertTrue(summary.hasPrefix("mitte gebucht · Padelon rückt nach · Rückfall Aspria "), summary)
    }

    func testStatusTextsReadLikeThePage() throws {
        XCTAssertEqual(PadelPlan.status(try occurrence("a", status: "SKIPPED", note: "ausgesetzt von felix")),
                       "ausgesetzt von felix")
        XCTAssertEqual(PadelPlan.status(try occurrence("b", status: "SKIPPED", note: "Zeit schon belegt")),
                       "ausgesetzt · Zeit schon belegt")
        XCTAssertEqual(PadelPlan.status(try occurrence("c", status: "MISSED")), "verpasst")
        XCTAssertTrue(PadelPlan.status(try occurrence("d", status: "WATCHING")).hasPrefix("rückt nach bis "))
    }

    func testFormats() {
        // 2026-11-06 17:00Z = Fr 06.11. 18:00 in Berlin (MEZ).
        let friday = Date(timeIntervalSince1970: 1_793_984_400)
        XCTAssertEqual(PadelFormat.when(friday), "Fr 06.11. 18:00")
        XCTAssertEqual(PadelFormat.when(friday, seconds: true), "Fr 06.11. 18:00:00")
        XCTAssertEqual(PadelFormat.dayLabel("2026-11-06", "Fr"), "Fr 06.11.")
        XCTAssertEqual(PadelFormat.countdown(to: friday, now: friday.addingTimeInterval(-3_725)), "in 01:02:05")
        XCTAssertEqual(PadelFormat.countdown(to: friday, now: friday.addingTimeInterval(-90_000)), "in 1 T 01:00:00")
        XCTAssertEqual(PadelFormat.countdown(to: friday, now: friday), "läuft")
        XCTAssertEqual(PadelFormat.price("16.88 EUR", split: true), "16,88 € p. P.")
        XCTAssertEqual(PadelFormat.price("60 EUR", split: false), "60 €")
        XCTAssertNil(PadelFormat.price(nil, split: true))
        XCTAssertEqual(PadelFormat.euro(1234.5), "1.234,50 €")
        XCTAssertEqual(PadelFormat.euro(0), "0,00 €")
        XCTAssertEqual(PadelFormat.matches(1), "1 Match")
        XCTAssertEqual(PadelFormat.matches(13), "13 Matches")
    }

    func testASeriesTitleShowsItsRange() throws {
        let json = """
        {"id":"s","weekday":"MONDAY","weekdayLabel":"Mo","start":"18:00","durationMinutes":90,"active":true,
         "latestStart":"21:30","club":"mitte","clubs":["mitte"],"partner":"b","partnerLabel":"Person B",
         "firstDate":"2026-11-06","partnerColor":"#14B8A6","levelLimit":true}
        """
        let series = try APIClient.decoder().decode(PadelSeries.self, from: Data(json.utf8))
        XCTAssertEqual(PadelPlan.title(series), "Mo · 18:00 bis 21:30 · 90′")
        XCTAssertEqual(series.levelLimit, true)
        XCTAssertNotNil(PadelColor.color(series.partnerColor))
        XCTAssertNil(PadelColor.color("nicht"))
    }

    func testANewSeriesSendsItsLevelChoiceAndPausingLeavesIt() throws {
        let new = PadelSeriesRequest(weekday: "MONDAY", start: "18:00", durationMinutes: 90, latestStart: nil,
                                     club: "mitte", partner: "b", levelLimit: true)
        let pause = PadelSeriesRequest(weekday: "MONDAY", start: "18:00", durationMinutes: 90, active: false,
                                       latestStart: nil, club: "mitte", partner: "b")
        let sent = try JSONSerialization.jsonObject(with: APIClient.encoder().encode(new)) as? [String: Any]
        let paused = try JSONSerialization.jsonObject(with: APIClient.encoder().encode(pause)) as? [String: Any]
        XCTAssertEqual(sent?["levelLimit"] as? Bool, true)
        XCTAssertNil(paused?["levelLimit"], "ohne Angabe laesst der Dienst die Eingrenzung, wie sie ist")
    }

    func testABookingSaysHowLongItCanBeCancelled() {
        let bookings = PadelDemo.bookings(now: now)
        XCTAssertTrue(PadelPlan.bookingLine(bookings[0]).hasPrefix("kostenlos stornierbar bis "))
        XCTAssertTrue(PadelPlan.bookingLine(bookings[0]).hasSuffix(" · Person A hat noch nicht bezahlt"))
        XCTAssertEqual(PadelPlan.bookingLine(bookings[1]), "öffentlich")
    }
}
