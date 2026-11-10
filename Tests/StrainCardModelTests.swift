import XCTest
@testable import Healthy

/// Die Strain-Karte im Dashboard (Vertrag §5, „0–21 mit Zielmarke“): was
/// gezeichnet wird, fuer jeden Sonderfall des Vertrags - der Simulator
/// bekommt keinen Puls, im Bild liesse sich das nie nachstellen.
final class StrainCardModelTests: XCTestCase {

    /// Ein Dienstag.
    private let today = CalendarDate(year: 2026, month: 11, day: 10)

    private func day(_ offset: Int, strain: Double?, target: Double? = 14.1,
                     status: StrainStatus = .ok) -> StrainDay {
        StrainDay(date: today.adding(days: -offset), status: strain == nil ? .noData : status,
                  partial: offset == 0, strain: strain, targetStrain: target)
    }

    // MARK: - Zahl, Ziel und Balken

    /// Unter dem Ziel: der Balken in der Strain-Farbe bis zum Strain, die
    /// Marke beim Ziel, nichts „über Ziel“.
    func testTodayBelowItsTarget() throws {
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: 12.4), week: [], on: today))
        XCTAssertEqual(model.value, "12,4")
        XCTAssertEqual(model.target, "Ziel 14,1")
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.fill, 12.4 / 21, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(bar.target), 14.1 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.base, 12.4 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.over, 0)
    }

    /// Ueber dem Ziel: Strain-Farbe bis zur Marke, der Rest in „über Ziel“.
    func testTodayOverItsTarget() throws {
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: 16.8, target: 12), week: [], on: today))
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.base, 12.0 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.over, 4.8 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.base + bar.over, bar.fill, accuracy: 1e-9)
    }

    /// Beim Kalibrieren gibt es noch kein Ziel: weder der Text noch die Marke,
    /// und nichts ist „über Ziel“.
    func testCalibratingHasNoTarget() throws {
        let model = try XCTUnwrap(StrainCardModel(
            today: day(0, strain: 9.3, target: nil, status: .calibrating), week: [], on: today))
        XCTAssertEqual(model.value, "9,3")
        XCTAssertNil(model.target)
        let bar = try XCTUnwrap(model.bar)
        XCTAssertNil(bar.target)
        XCTAssertEqual(bar.base, 9.3 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.over, 0)
    }

    /// Heute noch kein Puls (`NO_DATA`), aber die Woche hat Werte: „–“ statt
    /// der Zahl, ein leerer Balken - Ziel und Marke stehen trotzdem da.
    func testNoHistogramTodayKeepsTheTarget() throws {
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: nil, target: 13.2),
                                                  week: [day(1, strain: 10.5)], on: today))
        XCTAssertNil(model.value, "die Karte zeigt dann „–“")
        XCTAssertEqual(model.target, "Ziel 13,2")
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.fill, 0)
        XCTAssertEqual(try XCTUnwrap(bar.target), 13.2 / 21, accuracy: 1e-9)
        XCTAssertEqual(bar.over, 0)
    }

    /// Ein Strain ueber der Skala bleibt im Balken.
    func testValuesStayOnTheScale() throws {
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: 21, target: 20.9), week: [], on: today))
        XCTAssertEqual(model.bar?.fill, 1)
        XCTAssertEqual(StrainFormat.fraction(25), 1)
        XCTAssertEqual(StrainFormat.fraction(-1), 0)
    }

    // MARK: - Die Karte fehlt

    /// Weder heute noch in der Woche ein Strain: keine Karte - auch wenn es
    /// schon ein Ziel gaebe.
    func testWithoutAnyStrainThereIsNoCard() {
        XCTAssertNil(StrainCardModel(today: nil, week: [], on: today))
        XCTAssertNil(StrainCardModel(today: day(0, strain: nil, target: 13.2),
                                     week: (1...6).map { day($0, strain: nil) }, on: today))
    }

    // MARK: - Woche

    /// D−6 … D mit den Wochentagen, heute markiert; ein Tag ohne Wert hat
    /// keinen Balken, und ein Tag, der in der Antwort fehlt, auch nicht.
    func testWeekRunsFromSixDaysAgoToToday() throws {
        let week = [day(6, strain: 4.2), day(5, strain: nil), day(3, strain: 15.4), day(1, strain: 10.5),
                    day(0, strain: 12.4)]
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: 12.4), week: week, on: today))
        let bars = try XCTUnwrap(model.week)
        XCTAssertEqual(bars.map(\.label), ["Mi", "Do", "Fr", "Sa", "So", "Mo", "Di"])
        XCTAssertEqual(bars.map(\.date), (0...6).reversed().map { today.adding(days: -$0) })
        XCTAssertEqual(bars.map { $0.height != nil }, [true, false, false, true, false, true, true])
        XCTAssertEqual(try XCTUnwrap(bars[3].height), 15.4 / 21, accuracy: 1e-9)
        XCTAssertEqual(bars.map(\.isToday), [false, false, false, false, false, false, true])
    }

    /// Faellt `today` aus, steht derselbe Tag in der Woche - und umgekehrt
    /// zaehlt der Wert von `today`, wenn die Woche ihn (noch) nicht hat.
    func testTodayAndWeekStandInForEachOther() throws {
        let fromWeek = try XCTUnwrap(StrainCardModel(today: nil, week: [day(0, strain: 8.8)], on: today))
        XCTAssertEqual(fromWeek.value, "8,8")
        XCTAssertEqual(fromWeek.target, "Ziel 14,1")
        XCTAssertEqual(try XCTUnwrap(fromWeek.week?.last?.height), 8.8 / 21, accuracy: 1e-9)

        let fromToday = try XCTUnwrap(StrainCardModel(today: day(0, strain: 8.8), week: [], on: today))
        XCTAssertEqual(try XCTUnwrap(fromToday.week?.last?.height), 8.8 / 21, accuracy: 1e-9)
    }

    /// Nur die Woche hat Werte: die Karte steht, mit „–“ und ohne Balken oben.
    func testOnlyTheWeekHasValues() throws {
        let model = try XCTUnwrap(StrainCardModel(today: day(0, strain: nil, target: nil),
                                                  week: [day(2, strain: 6.1)], on: today))
        XCTAssertNil(model.value)
        XCTAssertNil(model.target)
        XCTAssertNil(model.bar, "weder Strain noch Ziel - nichts zu zeichnen")
        XCTAssertNotNil(model.week)
    }

    /// Ein ruhiger Tag bekommt mindestens einen duennen Strich - sonst saehe er
    /// aus wie ein Tag ohne Uhr.
    func testAQuietDayStillShowsABar() {
        XCTAssertEqual(StrainCardModel.barLength(0.01, in: 44), 2)
        XCTAssertEqual(StrainCardModel.barLength(0.5, in: 44), 22)
    }
}

/// Wie das Dashboard eine Antwort einordnet - fuer die freiwilligen Karten
/// (Strain, spaeter Briefing, Rueckblick, Serien, Chat) blendet ein 403 nur die
/// Karte aus (Vertrag §5).
@MainActor
final class DashboardTakeTests: XCTestCase {

    private struct Other: Error {}

    func testSuccessReplacesThePreviousValue() {
        var problems: [Backend] = []
        XCTAssertEqual(DashboardStore.take(.success(2), previous: 1, backend: .weight, problems: &problems), 2)
        XCTAssertTrue(problems.isEmpty)
    }

    /// Kein Zugang: die Karte fehlt, und der Dienst steht im Banner.
    func testMissingAccessRaisesTheBanner() {
        var problems: [Backend] = []
        let value: Int? = DashboardStore.take(.failure(APIError.notAuthorised), previous: 1, backend: .weight,
                                              problems: &problems)
        XCTAssertNil(value)
        XCTAssertEqual(problems, [.weight])
    }

    /// Eine freiwillige Karte: „nicht freigeschaltet“ - sie fehlt, ohne Banner.
    func testAnOptionalCardHidesWithoutTheBanner() {
        var problems: [Backend] = []
        let value: Int? = DashboardStore.take(.failure(APIError.notAuthorised), previous: 1, backend: .weight,
                                              problems: &problems, optional: true)
        XCTAssertNil(value)
        XCTAssertTrue(problems.isEmpty)
    }

    /// Ein 404 heisst „kennt dieser Dienst noch nicht“: die Karte fehlt. Alles
    /// andere laesst den letzten Stand stehen.
    func testUnknownEndpointHidesAndOtherErrorsKeepThePreviousValue() {
        var problems: [Backend] = []
        let missing: Int? = DashboardStore.take(.failure(APIError.http(404, nil)), previous: 1, backend: .weight,
                                                problems: &problems, optional: true)
        XCTAssertNil(missing)
        XCTAssertEqual(DashboardStore.take(.failure(Other()), previous: 1, backend: .weight,
                                           problems: &problems, optional: true), 1)
        XCTAssertEqual(DashboardStore.take(.failure(APIError.http(500, nil)), previous: 1, backend: .weight,
                                           problems: &problems), 1)
        XCTAssertTrue(problems.isEmpty)
    }
}
