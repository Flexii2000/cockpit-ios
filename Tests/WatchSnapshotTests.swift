import XCTest
@testable import Healthy

/// Der Stand, den die Uhr zeigt - seit 10.11. samt Makros.
final class WatchSnapshotTests: XCTestCase {

    private let consumed = Nutrients(kcal: 1550, proteinG: 96, carbsG: 180, fatG: 41)
    private let targets = Nutrients(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70, proteinMinG: 140)

    /// Was vor dem Update auf der Uhr lag, muss lesbar bleiben - sonst stuende
    /// dort bis zum naechsten Abruf „–“.
    func testAnOldSnapshotStillDecodes() throws {
        let old = #"{"date":"2026-11-10","consumedKcal":1550,"targetKcal":2300,"fetchedAt":784000000}"#
        let snapshot = try JSONDecoder().decode(ComplicationSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(snapshot.consumedKcal, 1550)
        XCTAssertEqual(snapshot.targetKcal, 2300)
        XCTAssertNil(snapshot.consumed)
        XCTAssertNil(snapshot.targets)
    }

    func testMacrosSurviveTheWayToTheWatch() throws {
        let sent = ComplicationSnapshot(date: "2026-11-10", consumedKcal: 1550, targetKcal: 2300,
                                        fetchedAt: Date(timeIntervalSinceReferenceDate: 784_000_000),
                                        consumed: consumed, targets: targets)
        let received = try JSONDecoder().decode(ComplicationSnapshot.self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(received, sent)
        XCTAssertEqual(received.targets?.proteinMinG, 140)
    }

    /// Ein anderer Zeitpunkt allein ist kein neuer Stand - geaenderte Makros schon.
    func testOnlyAChangedDayIsSentAgain() {
        let first = ComplicationSnapshot(date: "2026-11-10", consumedKcal: 1550, targetKcal: 2300,
                                         fetchedAt: Date(timeIntervalSinceReferenceDate: 1),
                                         consumed: consumed, targets: targets)
        let later = ComplicationSnapshot(date: "2026-11-10", consumedKcal: 1550, targetKcal: 2300,
                                         fetchedAt: Date(timeIntervalSinceReferenceDate: 500),
                                         consumed: consumed, targets: targets)
        XCTAssertTrue(later.showsSame(as: first))
        XCTAssertFalse(later.showsSame(as: nil))

        let moreProtein = ComplicationSnapshot(
            date: "2026-11-10", consumedKcal: 1550, targetKcal: 2300, fetchedAt: Date(),
            consumed: Nutrients(kcal: 1550, proteinG: 120, carbsG: 180, fatG: 41), targets: targets)
        XCTAssertFalse(moreProtein.showsSame(as: first))

        let newFloor = ComplicationSnapshot(
            date: "2026-11-10", consumedKcal: 1550, targetKcal: 2300, fetchedAt: Date(), consumed: consumed,
            targets: Nutrients(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70, proteinMinG: 150))
        XCTAssertFalse(newFloor.showsSame(as: first))
    }

    /// Die drei Zeilen unter dem kcal-Bogen (Vertrag §11.1).
    func testTheRowsOnTheWatch() {
        XCTAssertEqual(WatchMacroText.label(.protein, consumed: consumed, targets: targets), "E 96/195")
        XCTAssertEqual(WatchMacroText.label(.fat, consumed: consumed, targets: targets), "F 41/70")
        XCTAssertEqual(WatchMacroText.label(.carbs, consumed: consumed, targets: targets), "KH 180/236")
    }

    /// Die Eiweiss-Zeile in ihrer Farbe: rot unter dem Erhalt, gelb ab dem Erhalt, gruen ab dem Ziel.
    func testTheProteinRowFollowsTheFloor() {
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: consumed, targets: targets).watchColor, .red)
        let enough = Nutrients(kcal: 0, proteinG: 150, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: enough, targets: targets).watchColor, .yellow)
        let full = Nutrients(kcal: 0, proteinG: 200, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: full, targets: targets).watchColor, .green)
    }
}
