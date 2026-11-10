import XCTest
@testable import Healthy

/// Das Morgen-Briefing (Vertrag §8.3): welcher Text nach einer Antwort des
/// Dienstes dasteht, und was ueber den Start der App hinweg gemerkt wird.
final class BriefingTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 11, day: 10)

    /// Ein neuer Text ersetzt den alten.
    func testAFreshTextReplacesTheShownOne() {
        let done = Briefing(date: today, status: .done, text: " Neuer Text. \n")
        XCTAssertEqual(BriefingRule.text(shown: nil, after: done), "Neuer Text.")
        XCTAssertEqual(BriefingRule.text(shown: "Alter Text.", after: done), "Neuer Text.")
    }

    /// Waehrend der Dienst neu schreibt, bleibt der alte Text stehen - und
    /// scheitert der neue Lauf, gilt der alte weiter.
    func testWithoutTextTheShownOneStays() {
        XCTAssertEqual(BriefingRule.text(shown: "Alter Text.", after: Briefing(status: .running)), "Alter Text.")
        XCTAssertEqual(BriefingRule.text(shown: "Alter Text.", after: Briefing(status: .failed)), "Alter Text.")
        XCTAssertEqual(BriefingRule.text(shown: "Alter Text.",
                                         after: Briefing(status: .running, text: "Alter Text.")), "Alter Text.")
        XCTAssertNil(BriefingRule.text(shown: nil, after: Briefing(status: .running)), "ohne Text fehlt die Karte")
        XCTAssertNil(BriefingRule.text(shown: nil, after: Briefing(status: .none)))
        XCTAssertNil(BriefingRule.text(shown: nil, after: Briefing(status: .failed, text: "  ")))
    }

    /// Gemerkt wird nur der Text von heute - gestern ist kein Briefing mehr.
    func testMemoryOnlyCountsForToday() throws {
        let data = try XCTUnwrap(BriefingMemory.data(text: "Text von heute.", today: today))
        XCTAssertEqual(BriefingMemory.text(in: data, today: today), "Text von heute.")
        XCTAssertNil(BriefingMemory.text(in: data, today: today.adding(days: 1)))
        XCTAssertNil(BriefingMemory.text(in: nil, today: today))
        XCTAssertNil(BriefingMemory.text(in: Data("kaputt".utf8), today: today))
    }

    /// Die App ist der Wirt dieser Tests und startet dabei ganz normal. Ein
    /// Briefing fordert sie dann nicht an - jeder Lauf von `verify.sh` startete
    /// sonst eine Sitzung beim Dienst. Woran sie das merkt, liefert Xcode;
    /// bliebe es in einer neuen Fassung aus, faellt es hier auf.
    @MainActor
    func testTheHostOfTheseTestsRequestsNoBriefing() {
        XCTAssertTrue(BriefingStore.isTestHost)
    }
}
