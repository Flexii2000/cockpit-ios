import XCTest
@testable import Healthy

/// Freunde und Serien als Text (Vertrag §10.4 und §5) - wortgleich mit der
/// Android-App, damit beide Handys dasselbe zeigen.
final class FriendsFormatTests: XCTestCase {

    func testDaysLabelsAndRecord() {
        XCTAssertEqual(FriendsFormat.days(0), "0 Tage")
        XCTAssertEqual(FriendsFormat.days(1), "1 Tag")
        XCTAssertEqual(FriendsFormat.days(12), "12 Tage")
        XCTAssertEqual(FriendsFormat.days(1234), "1.234 Tage")
        XCTAssertEqual(FriendsFormat.record(30), "Rekord 30")
        XCTAssertEqual([StreakType.tracked, .protein, .steps, .kcal].map(FriendsFormat.label),
                       ["Tracking", "Eiweißziel", "Schrittziel", "Kalorienziel"])
        XCTAssertNil(FriendsFormat.label(.unknown), "eine Art, die die App nicht kennt, hat keine Zeile")
    }

    func testInitialOfTheFriend() {
        XCTAssertEqual(FriendsFormat.initial("person a"), "P")
        XCTAssertEqual(FriendsFormat.initial("  Ärmel"), "Ä")
        XCTAssertEqual(FriendsFormat.initial(""), "?")
        XCTAssertEqual(FriendsFormat.initial(nil), "?")
    }

    /// Die Serien-Kachel: „23 Tage“ und „12 Tage · Person A“.
    func testStreakTileTexts() {
        let tile = StreakTile(tracking: .init(current: 23, best: 41, todayDone: false),
                              topFriend: .init(friendshipId: "f-1", name: "Person A", type: .steps,
                                               current: 12, atRisk: true))
        XCTAssertEqual(FriendsFormat.tracking(tile), "23 Tage")
        XCTAssertEqual(FriendsFormat.topFriend(tile), "12 Tage · Person A")
        XCTAssertEqual(FriendsFormat.tracking(nil), "–")
        XCTAssertNil(FriendsFormat.topFriend(StreakTile(tracking: .init(current: 1), topFriend: nil)))
        XCTAssertEqual(FriendsFormat.tracking(StreakTile(tracking: .init(current: 1))), "1 Tag")
    }

    /// Eine Karte zeigt nur die Arten, die die App kennt.
    func testShownStreaksSkipUnknownTypes() {
        let friend = Friend(id: "f-1", name: "Person A", streaks: [
            FriendStreak(type: .tracked, current: 1, best: 1, me: .done, friend: .open, atRisk: false),
            FriendStreak(type: .unknown, current: 9, best: 9, me: .done, friend: .done, atRisk: false),
        ])
        XCTAssertEqual(friend.shownStreaks.map(\.type), [.tracked])
    }

    // MARK: - Code

    /// Allein in jeder Schreibweise, mitten im Text nur mit Bindestrich.
    func testCodeParsing() {
        XCTAssertEqual(FriendCode.parse("K7Q4-M2XD"), "K7Q4-M2XD")
        XCTAssertEqual(FriendCode.parse(" k7q4m2xd \n"), "K7Q4-M2XD")
        XCTAssertEqual(FriendCode.parse("k7q4 m2xd"), "K7Q4-M2XD")
        XCTAssertEqual(FriendCode.parse("Mein Code für Healthy: K7Q4-M2XD"), "K7Q4-M2XD")
        XCTAssertEqual(FriendCode.parse(FriendsFormat.shareText(code: "K7Q4-M2XD")), "K7Q4-M2XD",
                       "was die App teilt, liest sie auch wieder")
        XCTAssertNil(FriendCode.parse(""))
        XCTAssertNil(FriendCode.parse("K7Q4-M2X"), "zu kurz")
        XCTAssertNil(FriendCode.parse("K7Q4-M2XD9"), "zu lang")
        XCTAssertNil(FriendCode.parse("K7Q4-M2X0"), "0, 1, I und O gibt es in keinem Code")
        XCTAssertNil(FriendCode.parse("zwei Wörter, hier steht kein Code"),
                     "ohne Bindestrich wuerden zwei beliebige Woerter zu einem Code")
    }

    // MARK: - Schritte

    private let monday = CalendarDate(year: 2026, month: 11, day: 9)

    /// Immer Montag bis Sonntag; die Hoehen sind Anteile des groessten Werts.
    func testStepsWeek() throws {
        let steps = FriendSteps(weekStart: monday, days: [
            FriendStepsDay(date: monday, me: 8000, friend: 10000),
            FriendStepsDay(date: monday.adding(days: 1), me: 5000, friend: nil),
        ], me: 13000, friend: 10000, lastWeek: FriendStepsTotals(me: 71200, friend: 69800))
        let week = try XCTUnwrap(FriendsStepsWeek(steps, today: monday.adding(days: 1)))
        XCTAssertEqual(week.days.map(\.label), ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        XCTAssertEqual(week.days[0].me, 0.8)
        XCTAssertEqual(week.days[0].friend, 1)
        XCTAssertEqual(week.days[1].me, 0.5)
        XCTAssertNil(week.days[1].friend, "kein Wert, kein Balken")
        XCTAssertNil(week.days[2].me, "Tage, die noch kommen, sind leer")
        XCTAssertEqual(week.me, "13.000")
        XCTAssertEqual(week.friend, "10.000")
        XCTAssertEqual(week.lastWeek, "71.200 · 69.800")
    }

    /// Ohne einen einzigen Wert fehlt der Vergleich; ohne Wochenanfang und
    /// Summen rechnet die Ansicht beides aus dem, was da ist.
    func testStepsWeekWithoutValuesAndWithoutTotals() throws {
        XCTAssertNil(FriendsStepsWeek(nil, today: monday))
        XCTAssertNil(FriendsStepsWeek(FriendSteps(weekStart: monday, days: []), today: monday))
        XCTAssertNil(FriendsStepsWeek(FriendSteps(weekStart: monday,
                                                  days: [FriendStepsDay(date: monday, me: 0, friend: nil)]),
                                      today: monday))

        let wednesday = monday.adding(days: 2)
        let loose = FriendSteps(days: [FriendStepsDay(date: monday, me: 4000, friend: 2000),
                                       FriendStepsDay(date: wednesday, me: 1000, friend: nil)])
        let week = try XCTUnwrap(FriendsStepsWeek(loose, today: wednesday))
        XCTAssertEqual(week.days.first?.date, monday, "die Woche beginnt am Montag vor heute")
        XCTAssertEqual(week.me, "5.000")
        XCTAssertEqual(week.friend, "2.000")
        XCTAssertNil(week.lastWeek)
    }

    // MARK: - Fehler

    func testErrorTexts() {
        XCTAssertEqual(FriendsFormat.acceptError(APIError.http(404, nil)), "Diesen Code gibt es nicht (mehr).")
        XCTAssertEqual(FriendsFormat.acceptError(APIError.http(400, "Das ist dein eigener Code.")),
                       "Das ist dein eigener Code.")
        XCTAssertEqual(FriendsFormat.acceptError(APIError.http(409, "egal")), "Ihr seid schon befreundet.")
        XCTAssertEqual(FriendsFormat.acceptError(APIError.http(429, nil)), "Zu viele Versuche – später noch einmal.")
        XCTAssertEqual(FriendsFormat.acceptError(APIError.offline), "Kein Netz.")
        XCTAssertEqual(FriendsFormat.inviteError(APIError.http(409, nil)), "Es sind schon fünf Codes offen.")
        XCTAssertEqual(FriendsFormat.nudgeError(APIError.http(429, nil)), "Heute schon angestupst.")
    }
}
