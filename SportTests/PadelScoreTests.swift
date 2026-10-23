import XCTest
@testable import Sport

/// Das Zaehlen auf der Uhr (Felix, 23.10.): Golden und Silver Point, Tie-Break, Aufschlag
/// ueber Saetze hinweg samt Spieler links oder rechts - und was davon als Ergebnis an den
/// Padel-Dienst geht.
final class PadelScoreTests: XCTestCase {

    private func points(_ score: inout PadelScore, _ sides: [PadelSide]) {
        for side in sides { score.point(for: side) }
    }

    private func games(_ score: inout PadelScore, _ sides: [PadelSide]) {
        for side in sides { points(&score, Array(repeating: side, count: 4)) }
    }

    func testPointsCountUpToForty() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        points(&score, [.us, .us, .them])
        XCTAssertEqual(score.pointLabel(.us), "30")
        XCTAssertEqual(score.pointLabel(.them), "15")
        points(&score, [.us])
        XCTAssertEqual(score.pointLabel(.us), "40")
        points(&score, [.us])
        XCTAssertEqual(score.games, PadelPair(us: 1, them: 0))
        XCTAssertEqual(score.pointLabel(.us), "0")
    }

    func testGoldenPointDecidesAtFortyAll() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        points(&score, [.us, .us, .us, .them, .them, .them])
        XCTAssertTrue(score.isDecidingPoint)
        points(&score, [.them])
        XCTAssertEqual(score.games, PadelPair(us: 0, them: 1))
    }

    func testSilverPointPlaysOneAdvantageThenDecides() {
        var score = PadelScore(rule: .silver, firstServer: .us)
        points(&score, [.us, .us, .us, .them, .them, .them])
        XCTAssertFalse(score.isDecidingPoint, "beim ersten 40:40 wird um den Vorteil gespielt")
        points(&score, [.us])
        XCTAssertEqual(score.pointLabel(.us), "AD")
        XCTAssertEqual(score.pointLabel(.them), "40")
        points(&score, [.them])
        XCTAssertTrue(score.isDecidingPoint, "zweites 40:40: der naechste Punkt entscheidet")
        points(&score, [.them])
        XCTAssertEqual(score.games, PadelPair(us: 0, them: 1))
    }

    func testSilverPointAdvantageWins() {
        var score = PadelScore(rule: .silver, firstServer: .us)
        points(&score, [.us, .us, .us, .them, .them, .them, .us, .us])
        XCTAssertEqual(score.games, PadelPair(us: 1, them: 0))
    }

    func testServeAlternatesEachGameAndAcrossSets() {
        var score = PadelScore(rule: .golden, firstServer: .them)
        XCTAssertEqual(score.server, .them)
        games(&score, [.us])
        XCTAssertEqual(score.server, .us)
        // 6:1 - sieben Spiele, also schlaegt im naechsten Satz zuerst auf, wer nicht zuletzt dran war.
        games(&score, [.us, .us, .them, .us, .us, .us])
        XCTAssertEqual(score.sets, [PadelSetScore(us: 6, them: 1)])
        XCTAssertEqual(score.server, .us)
        games(&score, [.us])
        XCTAssertEqual(score.server, .them)
    }

    func testEachTeamAlternatesItsServerAcrossSets() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        XCTAssertEqual(score.servingPlayer, .right, "anfangs rechts")
        games(&score, [.us])
        XCTAssertEqual(score.server, .them)
        XCTAssertEqual(score.servingPlayer, .right, "die anderen schlagen zum ersten Mal auf")
        games(&score, [.us])
        XCTAssertEqual(score.server, .us)
        XCTAssertEqual(score.servingPlayer, .left, "bei uns ist jetzt der andere dran")
        // 6:0 - wir haben rechts, links, rechts aufgeschlagen; im neuen Satz geht es links weiter.
        games(&score, [.us, .us, .us, .us])
        XCTAssertEqual(score.sets, [PadelSetScore(us: 6, them: 0)])
        XCTAssertEqual(score.server, .us)
        XCTAssertEqual(score.servingPlayer, .left)
    }

    func testTappingTheBallSwitchesThePlayerAndTheRotationFollows() {
        var score = PadelScore(rule: .golden, firstServer: .them)
        score.switchServingPlayer()
        XCTAssertEqual(score.servingPlayer, .left)
        XCTAssertEqual(score.servers.us, .right, "nur im Team, das aufschlaegt")
        games(&score, [.them, .us])
        XCTAssertEqual(score.server, .them)
        XCTAssertEqual(score.servingPlayer, .right)
    }

    func testTieBreakRotatesThePlayersToo() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        games(&score, [.us, .them, .us, .them, .us, .them, .us, .them, .us, .them, .us, .them])
        // Zwoelf Spiele: jeder hat dreimal aufgeschlagen, dran ist wieder, wer anfing.
        XCTAssertEqual(score.server, .us)
        XCTAssertEqual(score.servingPlayer, .right)
        points(&score, [.us])
        XCTAssertEqual(score.server, .them)
        XCTAssertEqual(score.servingPlayer, .right)
        points(&score, [.us, .us])
        XCTAssertEqual(score.server, .us)
        XCTAssertEqual(score.servingPlayer, .left, "der Partner dessen, der eroeffnet hat")
        points(&score, [.us, .us])
        XCTAssertEqual(score.server, .them)
        XCTAssertEqual(score.servingPlayer, .left)
    }

    func testAScoreSavedBeforeThePlayersWereKeptStillLoads() throws {
        var score = PadelScore(rule: .golden, firstServer: .us)
        games(&score, [.us])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(score)) as? [String: Any])
        XCTAssertNotNil(json["storedServers"])
        json["storedServers"] = nil
        let old = try JSONDecoder().decode(PadelScore.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.server, .them)
        XCTAssertEqual(old.servingPlayer, .right)
    }

    func testSevenFiveEndsASetWithoutTieBreak() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        games(&score, [.us, .them, .us, .them, .us, .them, .us, .them, .us, .them, .us, .us])
        XCTAssertEqual(score.sets, [PadelSetScore(us: 7, them: 5)])
        XCTAssertFalse(score.isTieBreak)
    }

    func testTieBreakAtSixAllToSevenWithTwoAhead() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        games(&score, [.us, .them, .us, .them, .us, .them, .us, .them, .us, .them, .us, .them])
        XCTAssertTrue(score.isTieBreak)
        // Zwoelf Spiele gespielt: wer das erste aufschlug, eroeffnet den Tie-Break.
        XCTAssertEqual(score.server, .us)
        points(&score, [.us])
        XCTAssertEqual(score.server, .them, "nach dem ersten Punkt wechselt der Aufschlag")
        points(&score, [.them])
        XCTAssertEqual(score.server, .them, "danach je zwei Punkte")
        points(&score, [.us])
        XCTAssertEqual(score.server, .us)
        XCTAssertEqual(score.pointLabel(.us), "2")
        points(&score, [.us, .us, .us, .us, .them, .them, .them, .them, .them])
        XCTAssertTrue(score.isTieBreak, "6:6 im Tie-Break")
        XCTAssertEqual(score.pointLabel(.them), "6")
        points(&score, [.us, .us])
        XCTAssertEqual(score.sets.count, 1)
        XCTAssertEqual(score.sets[0].us, 7)
        XCTAssertEqual(score.sets[0].them, 6)
        XCTAssertEqual(score.sets[0].tieBreak, PadelPair(us: 8, them: 6))
        // Wer im Tie-Break zuerst annahm, schlaegt im neuen Satz zuerst auf.
        XCTAssertEqual(score.server, .them)
    }

    func testTwoSetsEndTheMatchAndLaterPointsAreIgnored() {
        var score = PadelScore(rule: .golden, firstServer: .us)
        games(&score, Array(repeating: .us, count: 6))
        games(&score, [.them, .us, .us, .us, .us, .us, .us])
        XCTAssertEqual(score.winner, .us)
        let finished = score
        points(&score, [.them])
        XCTAssertEqual(score, finished)
    }

    func testOnlyCompletedValidSetsMakeAReport() {
        var score = PadelScore(rule: .silver, firstServer: .us)
        games(&score, Array(repeating: .us, count: 6))
        games(&score, [.them, .them, .us])
        let report = PadelMatchReport(id: "r-1", startedAt: Date(), endedAt: Date(), rule: score.rule, sets: score.sets)
        XCTAssertEqual(report.summary, "6:0")
        XCTAssertTrue(report.isValid)
        XCTAssertFalse(PadelMatchReport(id: "r-2", startedAt: Date(), endedAt: Date(), rule: .golden, sets: []).isValid)
        XCTAssertFalse(PadelSetScore(us: 6, them: 5).isValid)
        XCTAssertTrue(PadelSetScore(us: 6, them: 7).isValid)
        XCTAssertFalse(PadelSetScore(us: 8, them: 6).isValid)
    }

    func testTheReportReadsLikeTheService() throws {
        let report = PadelMatchReport(id: "r-1", startedAt: Date(timeIntervalSince1970: 1_762_448_400),
                                      endedAt: Date(timeIntervalSince1970: 1_762_453_800), rule: .golden,
                                      sets: [PadelSetScore(us: 6, them: 0), PadelSetScore(us: 6, them: 2)])
        let json = try XCTUnwrap(String(data: APIClient.encoder().encode(report), encoding: .utf8))
        XCTAssertTrue(json.contains(#""startedAt":"2025-11-06T17:00:00Z""#), json)
        XCTAssertTrue(json.contains(#""rule":"golden""#), json)
        XCTAssertTrue(json.contains(#"{"them":0,"us":6}"#) || json.contains(#"{"us":6,"them":0}"#), json)
        XCTAssertEqual(try APIClient.decoder().decode(PadelMatchReport.self, from: Data(json.utf8)), report)
    }
}
