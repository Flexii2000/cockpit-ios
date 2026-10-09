import XCTest
@testable import Healthy

/// „Defizit ⌀" in den Diagrammen (Vertrag §5): die eigene Skala samt
/// Abbildung in die Achse des Diagramms und die Flaeche zwischen
/// „Verbrauch ⌀" und „kcal ⌀" - beides ist nur ueber diese Funktionen
/// pruefbar, eine Ziehgeste kann der Simulator nicht.
final class DeficitChartTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func day(_ dayOfMonth: Int) -> CalendarDate {
        CalendarDate(year: 2026, month: 10, day: dayOfMonth)
    }

    private func average(_ dayOfMonth: Int, _ kcal: Double, complete: Bool = true) -> DayAverage {
        DayAverage(date: day(dayOfMonth), kcal: kcal, days: 7, complete: complete)
    }

    // MARK: - Skala

    /// Nur Defizit: die Skala beginnt bei 0 und endet auf dem naechsten
    /// runden Schritt - wie im Web.
    func testScaleIncludesZero() {
        let scale = DeficitScale(values: [300, 620])
        XCTAssertEqual(scale.domain, 0...750)
        XCTAssertEqual(scale.step, 250)
        XCTAssertEqual(scale.ticks, [0, 250, 500, 750])
        XCTAssertEqual(scale.insideTicks, [0, 750], "innen nur 0 und der Rand")
    }

    /// Defizit und Ueberschuss: beide Seiten der Nulllinie, innen 0 und die
    /// beiden Raender - hoechstens zwei runde Werte neben der 0.
    func testScaleWithSurplus() {
        let scale = DeficitScale(values: [-150, 480, 210])
        XCTAssertEqual(scale.domain, -250...500)
        XCTAssertEqual(scale.ticks, [-250, 0, 250, 500])
        XCTAssertEqual(scale.insideTicks, [-250, 0, 500])
    }

    /// Nur Ueberschuss: die 0 ist der obere Rand.
    func testScaleWithOnlySurplus() {
        let scale = DeficitScale(values: [-300, -100])
        XCTAssertEqual(scale.domain, -500...0)
        XCTAssertEqual(scale.insideTicks, [-500, 0])
    }

    /// Eine Spanne ueber 1.500 kcal rechnet in 500er Schritten, und ohne
    /// Werte gibt es trotzdem einen Bereich mit zwei Schritten.
    func testScaleStepsAndEmptyValues() {
        let wide = DeficitScale(values: [-900, 1200])
        XCTAssertEqual(wide.step, 500)
        XCTAssertEqual(wide.domain, -1000...1500)
        XCTAssertEqual(DeficitScale(values: []).domain, 0...500)
        XCTAssertEqual(DeficitScale(values: [10]).domain, 0...500, "mindestens zwei Schritte")
    }

    /// Die Abbildung in die Achse des Diagramms muss in beide Richtungen
    /// stimmen - sonst stuende rechts eine andere Zahl, als die Kurve zeigt.
    func testScaleMapsOntoTheChartAndBack() {
        let scale = DeficitScale(values: [-150, 480])          // -250…500
        let kcalAxis = 1500.0...3000.0
        XCTAssertEqual(scale.position(-250, in: kcalAxis), 1500)
        XCTAssertEqual(scale.position(500, in: kcalAxis), 3000)
        XCTAssertEqual(scale.position(0, in: kcalAxis), 2000, "die Nulllinie liegt bei einem Drittel")
        XCTAssertEqual(scale.value(at: scale.position(318, in: kcalAxis), in: kcalAxis), 318, accuracy: 1e-9)
    }

    /// Im Essen-Verlauf: die Linie liegt auf der kcal-Achse, getrennt an
    /// Luecken und gestrichelt am vorlaeufigen Rand wie „Verbrauch ⌀".
    func testDeficitRunsOnTheKcalAxis() {
        let deficit = [average(1, 0), average(2, 250), average(4, 500), average(5, 250),
                       average(6, 0, complete: false)]
        let scale = DeficitScale(values: deficit.map(\.kcal))   // 0…500
        let runs = FoodChartData.deficitRuns(deficit, scale: scale, onto: 1500...2500)
        XCTAssertEqual(runs.map(\.samples.count), [2, 2, 2])
        XCTAssertEqual(runs.map(\.complete), [true, true, false])
        XCTAssertEqual(runs[0].samples.map(\.value), [1500, 2000])
        XCTAssertEqual(runs[1].samples.map(\.value), [2500, 2000])
        XCTAssertEqual(runs[2].samples.map(\.value), [2000, 1500], "der gestrichelte Teil setzt am festen an")
    }

    // MARK: - Flaeche

    /// Liegt der Verbrauch ueberall darueber, ist es ein Stueck in
    /// Defizit-Farbe.
    func testBandWithDeficitOnly() {
        let segments = EnergyBand.segments(expenditure: [average(1, 2800), average(2, 2750), average(3, 2700)],
                                           intake: [average(1, 2300), average(2, 2400), average(3, 2500)],
                                           in: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].isDeficit, true)
        XCTAssertEqual(segments[0].points.map(\.intake), [2300, 2400, 2500])
    }

    /// Kreuzen sich die Kurven zwischen zwei Tagen, wechselt die Farbe am
    /// Schnittpunkt - beide Stuecke enden dort, auf derselben Hoehe.
    func testBandSwitchesColourAtTheCrossing() throws {
        let segments = EnergyBand.segments(expenditure: [average(1, 2800), average(2, 2700)],
                                           intake: [average(1, 2600), average(2, 2900)], in: utc)
        XCTAssertEqual(segments.map(\.isDeficit), [true, false])
        let crossing = try XCTUnwrap(segments[0].points.last)
        XCTAssertEqual(segments[1].points.first, crossing)
        // +200 und −200: genau in der Mitte, um 12 Uhr.
        XCTAssertEqual(crossing.date, day(1).startOfDay(in: utc).addingTimeInterval(12 * 3600))
        XCTAssertEqual(crossing.expenditure, 2750, accuracy: 1e-9)
        XCTAssertEqual(crossing.intake, crossing.expenditure, accuracy: 1e-9)
    }

    /// Kein Stueck ueber eine Luecke einer der beiden Kurven, und nur dort,
    /// wo beide einen Wert haben.
    func testBandOnlyWhereBothCurvesHaveValues() {
        let expenditure = [1, 2, 3, 5, 6].map { average($0, 2800) }
        let intake = (2...7).map { average($0, 2400) }
        let segments = EnergyBand.segments(expenditure: expenditure, intake: intake, in: utc)
        XCTAssertEqual(segments.map { $0.points.map(\.date) },
                       [[day(2), day(3)], [day(5), day(6)]].map { $0.map { $0.startOfDay(in: utc) } })
        XCTAssertTrue(EnergyBand.segments(expenditure: [average(1, 2800)], intake: [average(1, 2400)],
                                          in: utc).isEmpty, "ein einzelner Tag hat keine Breite")
    }

    /// Beruehren sich die Kurven an einem Tag und wechseln dann die Seite,
    /// endet das Stueck an diesem Tag - ohne doppelten Punkt.
    func testBandSplitsAtATouchingDay() {
        let segments = EnergyBand.segments(
            expenditure: [average(1, 2800), average(2, 2600), average(3, 2500)],
            intake: [average(1, 2700), average(2, 2600), average(3, 2700)], in: utc)
        XCTAssertEqual(segments.map(\.isDeficit), [true, false])
        XCTAssertEqual(segments.map(\.points.count), [2, 2])
        XCTAssertEqual(segments[0].points.last, segments[1].points.first)
    }

    /// Im Gewicht-Diagramm wird die Flaeche in den Gewichtsbereich
    /// hineingerechnet; der Schnittpunkt bleibt, wo er war.
    func testBandIsMappedOntoTheChart() {
        let segments = EnergyBand.segments(expenditure: [average(1, 2800), average(2, 2700)],
                                           intake: [average(1, 2600), average(2, 2900)],
                                           map: { $0 / 100 }, in: utc)
        XCTAssertEqual(segments[0].points.first?.expenditure, 28)
        XCTAssertEqual(segments[0].points.first?.intake, 26)
        XCTAssertEqual(segments[0].points.last?.date,
                       day(1).startOfDay(in: utc).addingTimeInterval(12 * 3600))
    }
}
