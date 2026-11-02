import XCTest

/// Die Antwort von claude.ai in der Form vom 02.11.2026 - Zahlen erfunden.
/// Die Schnittstelle ist intern und ohne Vertrag; diese Tests halten fest, was
/// die App davon liest, und dass Fremdes sie nicht kippt.
final class ClaudeUsageTests: XCTestCase {

    private let sample = #"""
    {"five_hour": null,
     "seven_day": {"utilization": 62.0, "resets_at": "2026-11-09T11:00:00.147565+00:00",
                   "limit_dollars": null, "locked_reason": null},
     "seven_day_opus": null,
     "extra_usage": {"is_enabled": false, "monthly_limit": null},
     "limits": [
       {"group": "weekly", "is_active": true, "kind": "weekly_all", "percent": 62,
        "resets_at": "2026-11-09T10:59:59.926185+00:00", "scope": null, "severity": "normal"},
       {"group": "weekly", "is_active": false, "kind": "weekly_scoped", "percent": 18,
        "resets_at": "2026-11-09T10:59:59.926374+00:00",
        "scope": {"model": {"display_name": "Fable", "id": null}, "surface": null}, "severity": "normal"},
       {"kind": "something_new", "percent": "not a number"}
     ],
     "seven_day_breakdown": {"as_of": "2026-11-05T09:28:52.938685+00:00",
       "window_started_at": "2026-11-02T10:59:59.926185+00:00",
       "rows": [{"display_name": "Claude Code", "key": "claude_code", "percent": 71},
                {"display_name": "Chats", "key": "chat", "percent": 24},
                {"display_name": "Cowork", "key": "cowork", "percent": 5},
                {"display_name": "Sonstige", "key": "other", "percent": 0}]},
     "spend": {"enabled": false, "percent": 0, "used": {"amount_minor": 0, "currency": "USD", "exponent": 2}},
     "weekly_scoped_shares": [{"allowance_percent_of_weekly": 50, "limit_index": 1, "used_percent_of_weekly": 6}]}
    """#

    func testReadsWeekScopedLimitsAndBreakdown() throws {
        let usage = try ClaudeUsage.parse(Data(sample.utf8))
        XCTAssertEqual(usage.weekly?.percent, 62)
        XCTAssertEqual(usage.weekly?.resetsAt, ClaudeUsage.date("2026-11-09T10:59:59+00:00"))
        XCTAssertEqual(usage.scoped.map(\.title), ["Fable"])
        XCTAssertEqual(usage.scoped.first?.percent, 18)
        XCTAssertNil(usage.session)
        XCTAssertEqual(usage.breakdown.map(\.key), ["claude_code", "chat", "cowork", "other"])
        XCTAssertEqual(usage.breakdown.map(\.percent), [71, 24, 5, 0])
        XCTAssertEqual(usage.weekStartedAt, ClaudeUsage.date("2026-11-02T10:59:59+00:00"))
        XCTAssertNil(usage.extra, "Zusatznutzung ist aus")
    }

    func testFallsBackToSevenDayWithoutLimits() throws {
        let json = #"{"five_hour": {"utilization": 12.5, "resets_at": "2026-11-02T15:00:00+00:00"},"#
            + #" "seven_day": {"utilization": 40, "resets_at": "2026-11-09T11:00:00.5+00:00"}}"#
        let usage = try ClaudeUsage.parse(Data(json.utf8))
        XCTAssertEqual(usage.weekly?.percent, 40)
        XCTAssertEqual(usage.weekly?.resetsAt, ClaudeUsage.date("2026-11-09T11:00:00Z"))
        XCTAssertEqual(usage.session?.percent, 12.5)
        XCTAssertEqual(usage.session?.title, "5 Stunden")
    }

    func testExtraUsageWhenEnabled() throws {
        let json = #"{"spend": {"enabled": true, "used": {"amount_minor": 1230, "currency": "USD", "exponent": 2},"#
            + #" "limit": {"amount_minor": 5000, "currency": "USD", "exponent": 2}}}"#
        let usage = try ClaudeUsage.parse(Data(json.utf8))
        XCTAssertEqual(usage.extra, ClaudeUsage.Extra(used: 12.3, limit: 50, currency: "USD"))
        XCTAssertNil(usage.weekly)
    }

    func testHtmlIsNotUsage() {
        XCTAssertThrowsError(try ClaudeUsage.parse(Data("<html>Just a moment…</html>".utf8)))
    }

    func testDatesWithMicroseconds() {
        XCTAssertNotNil(ClaudeUsage.date("2026-11-02T11:00:00.147565+00:00"))
        XCTAssertNotNil(ClaudeUsage.date("2026-11-02T11:00:00Z"))
        XCTAssertNil(ClaudeUsage.date("gestern"))
    }

    func testWeekElapsed() throws {
        let usage = try ClaudeUsage.parse(Data(sample.utf8))
        let start = try XCTUnwrap(usage.weekStartedAt)
        XCTAssertEqual(try XCTUnwrap(usage.weekElapsed(at: start.addingTimeInterval(3.5 * 86_400))), 0.5, accuracy: 0.001)
        XCTAssertEqual(usage.weekElapsed(at: start.addingTimeInterval(-60)), 0)
        XCTAssertEqual(ClaudeUsageFormat.weekDay(usage, now: start.addingTimeInterval(60)), "Tag 1 von 7")
        XCTAssertEqual(ClaudeUsageFormat.weekDay(usage, now: start.addingTimeInterval(6.99 * 86_400)), "Tag 7 von 7")
    }

    // MARK: - Organisation

    func testPicksTheSubscriptionNotTheApiOrganization() throws {
        let json = #"[{"uuid": "org-a", "capabilities": ["chat", "claude_max"]},"#
            + #" {"uuid": "org-b", "capabilities": ["api", "api_individual"]}]"#
        let all = try JSONDecoder().decode([ClaudeOrganization].self, from: Data(json.utf8))
        XCTAssertEqual(ClaudeOrganization.pick(all, lastActive: nil)?.uuid, "org-a")
        XCTAssertEqual(ClaudeOrganization.pick(all, lastActive: "org-b")?.uuid, "org-a",
                       "die API-Organisation hat kein Abo, auch wenn sie zuletzt aktiv war")
        let two = all + [ClaudeOrganization(uuid: "org-c", capabilities: ["chat"])]
        XCTAssertEqual(ClaudeOrganization.pick(two, lastActive: "org-c")?.uuid, "org-c")
    }

    // MARK: - Mitteilungen

    func testThresholdsOncePerWeekAndOnlyTheHighest() {
        let reset = ClaudeUsage.date("2026-11-09T10:59:59.9+00:00")
        var state = Thresholds()

        var result = state.check(percent: 45, resetsAt: reset)
        XCTAssertNil(result.due)
        state = result.next

        result = state.check(percent: 52, resetsAt: reset)
        XCTAssertEqual(result.due, 50)
        state = result.next

        result = state.check(percent: 55, resetsAt: reset)
        XCTAssertNil(result.due, "50 % schon gemeldet")
        state = result.next

        // Mac war zu - von 55 auf 93: nur die 90 kommt.
        result = state.check(percent: 93, resetsAt: reset)
        XCTAssertEqual(result.due, 90)
        XCTAssertEqual(result.next.sent, [50, 75, 90])
        state = result.next

        // Derselbe Reset, ein paar Millisekunden anders gemeldet: dieselbe Woche.
        result = state.check(percent: 94, resetsAt: ClaudeUsage.date("2026-11-09T11:00:00.2+00:00"))
        XCTAssertNil(result.due)
        state = result.next

        result = state.check(percent: 100, resetsAt: reset)
        XCTAssertEqual(result.due, 100)
        state = result.next

        // Neue Woche: alles von vorn.
        let nextWeek = ClaudeUsage.date("2026-11-16T11:00:00+00:00")
        result = state.check(percent: 3, resetsAt: nextWeek)
        XCTAssertNil(result.due)
        XCTAssertEqual(result.next.sent, [])
        result = result.next.check(percent: 51, resetsAt: nextWeek)
        XCTAssertEqual(result.due, 50)
    }

    // MARK: - Formate

    func testFormats() {
        XCTAssertEqual(ClaudeUsageFormat.percent(62.4), "62 %")
        XCTAssertEqual(ClaudeUsageFormat.percent(nil), "–")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClaudeUsageFormat.remaining(until: now.addingTimeInterval(91 * 60), now: now), "in 1 h 31 min")
        XCTAssertEqual(ClaudeUsageFormat.remaining(until: now.addingTimeInterval(3 * 86_400 + 4 * 3_600), now: now), "in 3 T 4 h")
        XCTAssertEqual(ClaudeUsageFormat.remaining(until: now.addingTimeInterval(12 * 60), now: now), "in 12 min")
        XCTAssertEqual(ClaudeUsageFormat.remaining(until: now.addingTimeInterval(-5), now: now), "jetzt")
        XCTAssertEqual(ClaudeUsageFormat.money(12.3, currency: "USD"), "12,30 $")
    }

    func testResetTimeNamesTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Mo 02.11.2026, 09:00 Berlin
        let now = ClaudeUsage.date("2026-11-02T08:00:00Z")!
        let laterToday = ClaudeUsage.date("2026-11-02T11:00:00Z")!
        let tomorrow = ClaudeUsage.date("2026-11-03T11:00:00Z")!
        XCTAssertTrue(ClaudeUsageFormat.resetTime(laterToday, now: now, calendar: calendar).hasPrefix("heute "))
        XCTAssertTrue(ClaudeUsageFormat.resetTime(tomorrow, now: now, calendar: calendar).hasPrefix("morgen "))
    }
}
