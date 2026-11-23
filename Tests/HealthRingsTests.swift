import XCTest
@testable import Healthy

/// Die Ringe-Komplikation der Uhr (Felix, 20.11.): kcal, Schritte, Strain.
final class HealthRingsTests: XCTestCase {

    // MARK: - Ringe

    func testEachRingFillsUpToItsTarget() {
        let rings = HealthRings.sample
        XCTAssertEqual(rings.kcal.fill, 1550.0 / 2300, accuracy: 0.0001)
        XCTAssertEqual(rings.steps.fill, 0.8214, accuracy: 0.0001)
        XCTAssertEqual(rings.strain.fill, 12.4 / 14.1, accuracy: 0.0001)
        XCTAssertEqual(rings.all.map(\.value), ["750", "8.214", "12,4"])
        XCTAssertFalse(rings.strain.over)
    }

    /// Ueber dem Ziel bleibt jeder Ring voll; der Strain wird orange (`over`),
    /// unter dem kcal-Ring steht der Ueberschuss mit Plus.
    func testAboveTheTargetTheRingStaysFull() {
        let rings = HealthRings(kcalConsumed: 2420, kcalTarget: 2300, steps: 12_345, stepsGoal: 10_000,
                                strain: 15.2, targetStrain: 14.1)
        XCTAssertEqual(rings.all.map(\.fill), [1, 1, 1])
        XCTAssertEqual(rings.all.map(\.value), ["+120", "12.345", "15,2"])
        XCTAssertTrue(rings.strain.over)
        XCTAssertEqual(rings.strain.spoken, "15,2, Ziel 14,1")
    }

    /// Ohne Ziel (Kalibrieren) misst der Strain-Ring an der ganzen Skala.
    func testWithoutATargetTheStrainRingUsesTheScale() {
        let rings = HealthRings(kcalConsumed: nil, kcalTarget: nil, steps: nil, stepsGoal: 10_000,
                                strain: 10.5, targetStrain: nil)
        XCTAssertEqual(rings.strain.fill, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rings.strain.value, "10,5")
        XCTAssertFalse(rings.strain.over)
    }

    /// Nie eine erfundene Zahl: ohne Wert „–“ und ein leerer Ring - auch beim
    /// Strain, wenn das Ziel schon da ist, der erste Puls des Tages aber nicht.
    func testMissingValuesShowADash() {
        let rings = HealthRings(kcalConsumed: nil, kcalTarget: 2300, steps: nil, stepsGoal: 10_000,
                                strain: nil, targetStrain: 14.1)
        XCTAssertEqual(rings.all.map(\.value), ["–", "–", "–"])
        XCTAssertEqual(rings.all.map(\.fill), [0, 0, 0])
        XCTAssertEqual(rings.strain.spoken, "noch kein Wert, Ziel 14,1")
    }

    func testZeroStepsIsANumber() {
        let rings = HealthRings(kcalConsumed: 0, kcalTarget: 2300, steps: 0, stepsGoal: 10_000,
                                strain: 0, targetStrain: 14.1)
        XCTAssertEqual(rings.all.map(\.value), ["2300", "0", "0,0"])
    }

    // MARK: - Letzter Stand

    private let today = "2026-11-20"

    func testFreshValuesWin() {
        let stored = RingsSnapshot(date: today, steps: 3000, stepsGoal: 9000, strain: 4.0, targetStrain: 13.0)
        let fresh = RingsFetch(steps: 5000, stepsGoal: 10_000,
                               strain: WatchStrain(date: today, strain: 6.1, targetStrain: 14.1))
        XCTAssertEqual(RingsSnapshot.merged(fresh, stored: stored, today: today),
                       RingsSnapshot(date: today, steps: 5000, stepsGoal: 10_000, strain: 6.1, targetStrain: 14.1))
    }

    /// Uhr gesperrt, kein Netz: der Stand von heute gilt weiter.
    func testWithoutAnswersTodaysStandStays() {
        let stored = RingsSnapshot(date: today, steps: 3000, stepsGoal: 9000, strain: 4.0, targetStrain: 13.0)
        XCTAssertEqual(RingsSnapshot.merged(RingsFetch(), stored: stored, today: today), stored)
    }

    /// Nach Mitternacht zaehlt der Stand von gestern nicht - nur das Schrittziel bleibt.
    func testYesterdaysStandDoesNotCountToday() {
        let stored = RingsSnapshot(date: "2026-11-19", steps: 11_000, stepsGoal: 9000, strain: 14.0,
                                   targetStrain: 13.0)
        XCTAssertEqual(RingsSnapshot.merged(RingsFetch(), stored: stored, today: today),
                       RingsSnapshot(date: today, steps: nil, stepsGoal: 9000, strain: nil, targetStrain: nil))
    }

    /// Ohne Netz kann der Offline-Stand der Abfrage von gestern stammen - der gilt nicht.
    func testAStrainFromAnotherDayIsIgnored() {
        let stored = RingsSnapshot(date: today, steps: nil, stepsGoal: nil, strain: 2.0, targetStrain: 14.1)
        let stale = RingsFetch(strain: WatchStrain(date: "2026-11-19", strain: 15.0, targetStrain: 12.0))
        let merged = RingsSnapshot.merged(stale, stored: stored, today: today)
        XCTAssertEqual(merged.strain, 2.0)
        XCTAssertEqual(merged.targetStrain, 14.1)
    }

    /// Antwortet der Weight Tracker ohne Strain (noch kein Puls heute), gilt das.
    func testAnAnswerWithoutStrainReplacesTheStand() {
        let stored = RingsSnapshot(date: today, steps: nil, stepsGoal: nil, strain: 2.0, targetStrain: 14.1)
        let fresh = RingsFetch(strain: WatchStrain(date: today, strain: nil, targetStrain: 14.1))
        XCTAssertNil(RingsSnapshot.merged(fresh, stored: stored, today: today).strain)
    }

    /// Im Laufe des Tages werden es nur mehr Schritte - der Ring springt nicht zurueck.
    func testStepsNeverGoBackWithinADay() {
        let stored = RingsSnapshot(date: today, steps: 6000, stepsGoal: nil, strain: nil, targetStrain: nil)
        XCTAssertEqual(RingsSnapshot.merged(RingsFetch(steps: 5800), stored: stored, today: today).steps, 6000)
    }

    func testTheStrainAnswerDecodes() throws {
        let json = #"{"date":"2026-11-20","status":"OK","partial":true,"strain":12.4,"targetStrain":14.1,"band":"MODERATE"}"#
        let strain = try APIClient.decoder().decode(WatchStrain.self, from: Data(json.utf8))
        XCTAssertEqual(strain, WatchStrain(date: today, strain: 12.4, targetStrain: 14.1))
        let noData = #"{"date":"2026-11-20","status":"NO_DATA","partial":true,"targetStrain":14.1}"#
        XCTAssertNil(try APIClient.decoder().decode(WatchStrain.self, from: Data(noData.utf8)).strain)
    }

    // MARK: - Auffrischen und Zugang

    func testRefreshEveryQuarterHourAndRightAfterMidnight() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12)))
        XCTAssertEqual(HealthRings.nextRefresh(after: noon, in: berlin), noon.addingTimeInterval(15 * 60))
        let late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 23,
                                                                     minute: 55)))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)))
        XCTAssertEqual(HealthRings.nextRefresh(after: late, in: berlin), midnight.addingTimeInterval(60))
    }

    /// Der Weight Tracker kennt `fh_private` nicht; der persoenliche Token geht vor.
    func testTheWeightTrackerGetsItsOwnCookie() {
        XCTAssertEqual(HealthCookie.weightHeader(health: nil, weight: "w"), "weight_app_token=w")
        XCTAssertEqual(HealthCookie.weightHeader(health: "h", weight: "w"), "health_token=h")
        XCTAssertNil(HealthCookie.weightHeader(health: "", weight: nil))
    }
}
