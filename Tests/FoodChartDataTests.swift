import XCTest
@testable import Healthy

/// Genau die drei Fehler, die im Verlauf des Kalorienzaehlers steckten -
/// alle drei mit derselben Ursache: der Zeitbereich kam aus den vorhandenen
/// Daten statt aus dem gewaehlten Zeitraum.
final class FoodChartDataTests: XCTestCase {

    private func day(_ month: Int, _ day: Int) -> CalendarDate {
        CalendarDate(year: 2026, month: month, day: day)
    }

    private func total(_ month: Int, _ dayOfMonth: Int, kcal: Double) -> DayTotal {
        let json = """
        {"date":"2026-\(String(format: "%02d", month))-\(String(format: "%02d", dayOfMonth))",
         "consumed":{"kcal":\(kcal),"proteinG":0,"carbsG":0,"fatG":0}}
        """
        return try! APIClient.decoder().decode(DayTotal.self, from: Data(json.utf8))
    }

    private func average(_ month: Int, _ dayOfMonth: Int, kcal: Double, complete: Bool = true) -> DayAverage {
        let json = """
        {"date":"2026-\(String(format: "%02d", month))-\(String(format: "%02d", dayOfMonth))",
         "kcal":\(kcal),"days":7,"complete":\(complete)}
        """
        return try! APIClient.decoder().decode(DayAverage.self, from: Data(json.utf8))
    }

    /// Das Mittel bricht an einer Luecke ab und wechselt am vorlaeufigen Rand
    /// in einen eigenen, gepunkteten Lauf - der am letzten festen Punkt
    /// ansetzt, damit die Linie nicht abreisst.
    func testAverageRunsSplitAtGapsAndAtTheProvisionalEdge() {
        let averages = [average(8, 1, kcal: 2000), average(8, 2, kcal: 2050),
                        average(8, 10, kcal: 2100), average(8, 11, kcal: 2150),
                        average(8, 12, kcal: 2200, complete: false),
                        average(8, 13, kcal: 2250, complete: false)]
        let runs = FoodChartData.averageRuns(averages)
        XCTAssertEqual(runs.map(\.samples.count), [2, 2, 3])
        XCTAssertEqual(runs.map(\.complete), [true, true, false])
        // Der gepunktete Lauf beginnt am 11., dem letzten festen Punkt.
        XCTAssertEqual(runs[2].samples.first?.value, 2150)
        XCTAssertEqual(runs[2].samples.first?.date, runs[1].samples.last?.date)
    }

    /// Nur das Mittel sichtbar: die Achse richtet sich nicht nach den
    /// Tageswerten, die ein Vielfaches ausschlagen koennen.
    func testKcalDomainFollowsWhatIsShown() {
        let daily = [total(8, 1, kcal: 3400), total(8, 2, kcal: 1200)]
        let averages = [average(8, 1, kcal: 2200), average(8, 2, kcal: 2250)]
        let onlyAverage = FoodChartData.kcalDomain(daily: [], averages: averages, target: 2300)
        let both = FoodChartData.kcalDomain(daily: daily, averages: averages, target: 2300)
        XCTAssertLessThan(onlyAverage.upperBound, both.upperBound)
        XCTAssertGreaterThanOrEqual(both.upperBound, 3400 + 150)
    }

    private func weightPoint(_ month: Int, _ dayOfMonth: Int, avg7: Double) -> WeightPoint {
        let json = """
        {"date":"2026-\(String(format: "%02d", month))-\(String(format: "%02d", dayOfMonth))",
         "measured":null,"avg7":\(avg7),"avg14":null,"avg30":null,
         "avg7Complete":true,"avg14Complete":false,"avg30Complete":false,"target":90}
        """
        return try! APIClient.decoder().decode(WeightPoint.self, from: Data(json.utf8))
    }

    /// Der eigentliche Fehler: die Gewichtskurve wurde auf den ersten Tag mit
    /// kcal-Eintrag zugeschnitten. Bei zwei erfassten Tagen blieben zwei
    /// Punkte uebrig - obwohl fuer den Zeitraum 30 Gewichtswerte vorlagen.
    func testWeightIsClippedToTheWindowNotToTheFoodData() {
        let points = (1...30).map { weightPoint(8, $0, avg7: 90 + Double($0) * 0.1) }
        let values = FoodChartData.weightValues(points, series: .avg7, from: day(8, 1), to: day(8, 30))
        XCTAssertEqual(values.count, 30, "Das Fenster entscheidet, nicht die kcal-Datenlage")
    }

    func testWeightOutsideTheWindowIsDropped() {
        let points = [weightPoint(7, 15, avg7: 95), weightPoint(8, 10, avg7: 92),
                      weightPoint(9, 20, avg7: 90)]
        let values = FoodChartData.weightValues(points, series: .avg7, from: day(8, 1), to: day(8, 31))
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.date, day(8, 10))
    }

    /// Mittel und Tageswerte sind zwei Serien, nicht eine mit Rueckfall:
    /// frueher wurde `avg7 ?? measured` genommen - damit haette der Schalter
    /// "Gewicht taeglich" an Tagen ohne Messung heimlich das Mittel gezeigt.
    func testAverageAndDailyAreSeparateSeries() {
        let json = Data(#"{"date":"2026-08-10","measured":91.3,"avg7":90.8,"avg14":null,"avg30":null,"avg7Complete":true,"avg14Complete":false,"avg30Complete":false,"target":90}"#.utf8)
        let point = try! APIClient.decoder().decode(WeightPoint.self, from: json)
        let average = FoodChartData.weightValues([point], series: .avg7,
                                                 from: day(8, 1), to: day(8, 31))
        let daily = FoodChartData.weightValues([point], series: .measured,
                                               from: day(8, 1), to: day(8, 31))
        XCTAssertEqual(average.first?.value, 90.8)
        XCTAssertEqual(daily.first?.value, 91.3)
    }

    /// An Tagen ohne Messung fehlt der Tageswert - dort darf nicht das Mittel
    /// einspringen.
    func testDailySeriesSkipsDaysWithoutMeasurement() {
        let json = Data(#"{"date":"2026-08-11","measured":null,"avg7":90.8,"avg14":null,"avg30":null,"avg7Complete":true,"avg14Complete":false,"avg30Complete":false,"target":90}"#.utf8)
        let point = try! APIClient.decoder().decode(WeightPoint.self, from: json)
        XCTAssertTrue(FoodChartData.weightValues([point], series: .measured,
                                                 from: day(8, 1), to: day(8, 31)).isEmpty)
        XCTAssertEqual(FoodChartData.weightValues([point], series: .avg7,
                                                  from: day(8, 1), to: day(8, 31)).count, 1)
    }

    func testWeightWithoutAnyValueIsSkipped() {
        let json = """
        {"date":"2026-08-10","measured":null,"avg7":null,"avg14":null,"avg30":null,
         "avg7Complete":false,"avg14Complete":false,"avg30Complete":false,"target":null}
        """
        let empty = try! APIClient.decoder().decode(WeightPoint.self, from: Data(json.utf8))
        XCTAssertTrue(FoodChartData.weightValues([empty], series: .avg7, from: day(8, 1), to: day(8, 31)).isEmpty)
    }

    /// Tage ohne Eintrag liefert der Kalorienzaehler gar nicht. Die Linie darf
    /// nicht darueber hinweggezogen werden.
    func testKcalLineBreaksAtGaps() {
        let history = [total(8, 30, kcal: 2100), total(8, 31, kcal: 2166),
                       total(9, 1, kcal: 2302)]
        XCTAssertEqual(FoodChartData.kcalRuns(history).count, 1)

        let withGap = [total(8, 10, kcal: 2000), total(8, 11, kcal: 2100),
                       total(8, 20, kcal: 1900), total(8, 21, kcal: 2000)]
        let runs = FoodChartData.kcalRuns(withGap)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].samples.count, 2)
        XCTAssertFalse(runs[0].isSingle)
    }

    /// Ein einzelner Tag zwischen zwei Luecken ergibt keine Linie - er muss
    /// als Punkt erkennbar sein, sonst fehlt er im Bild.
    func testIsolatedDayIsMarkedAsSingle() {
        let runs = FoodChartData.kcalRuns([total(8, 5, kcal: 2000)])
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].isSingle)
    }

    func testDaysOverTargetNeedMoreThanTheTolerance() {
        let history = [total(8, 1, kcal: 2350),   // +50, noch im Rahmen
                       total(8, 2, kcal: 2450)]   // +150, drueber
        let over = FoodChartData.daysOverTarget(history, target: 2300, tolerance: 100)
        XCTAssertEqual(over.count, 1)
        XCTAssertEqual(over.first?.date, day(8, 2))
    }

    func testWithoutTargetNothingIsMarkedAsOver() {
        let history = [total(8, 1, kcal: 5000)]
        XCTAssertTrue(FoodChartData.daysOverTarget(history, target: nil, tolerance: 100).isEmpty)
    }

    /// Die kcal-Achse faengt nicht bei null an - sonst saesse der
    /// interessante Bereich in ein paar Pixeln.
    func testKcalAxisDoesNotStartAtZero() {
        let domain = FoodChartData.kcalDomain([total(8, 1, kcal: 2100)], target: 2300)
        XCTAssertGreaterThan(domain.lowerBound, 1000)
        XCTAssertLessThanOrEqual(domain.lowerBound, FoodChartData.kcalBase)
        XCTAssertGreaterThan(domain.upperBound, 2300)
    }

    func testKcalAxisStaysUsableWithoutData() {
        let domain = FoodChartData.kcalDomain([], target: nil)
        XCTAssertLessThan(domain.lowerBound, domain.upperBound)
    }

    /// Die Umrechnung zwischen den beiden Skalen muss in beide Richtungen
    /// zusammenpassen - sonst behauptet die rechte Achse etwas anderes, als
    /// die Kurve zeigt.
    func testScalingIsReversible() {
        let weight = 91.4
        let source = 89.0...93.0
        let target = 1500.0...2800.0
        let mapped = FoodChartData.scale(weight, from: source, to: target)
        let back = FoodChartData.scale(mapped, from: target, to: source)
        XCTAssertEqual(back, weight, accuracy: 0.0001)
    }

    func testScalingSurvivesADegenerateRange() {
        let value = FoodChartData.scale(5, from: 3.0...3.0, to: 1000.0...2000.0)
        XCTAssertEqual(value, 1000)
    }

    // MARK: - Verbrauch ⌀

    /// Der Verbrauch liegt meist ueber allem Gegessenen - die Achse muss ihn
    /// fassen, sonst ragte seine Kurve oben hinaus.
    func testKcalDomainMakesRoomForTheExpenditure() {
        let averages = [average(10, 1, kcal: 2100), average(10, 2, kcal: 2150)]
        let expenditure = [average(10, 1, kcal: 2950), average(10, 2, kcal: 3010)]
        let without = FoodChartData.kcalDomain(daily: [], averages: averages, target: 2300)
        let with = FoodChartData.kcalDomain(daily: [], averages: averages, expenditure: expenditure,
                                            target: 2300)
        XCTAssertLessThan(without.upperBound, 3010)
        XCTAssertGreaterThan(with.upperBound, 3010)
    }

    /// „Verbrauch ⌀" kommt aus dem Weight Tracker und zerfaellt wie „kcal ⌀":
    /// an Luecken (Tage ohne Uhr) und am vorlaeufigen Rand, gestrichelt.
    func testExpenditureRunsBreakAtGapsAndTheProvisionalEdge() throws {
        let json = Data("""
        [{"date":"2026-10-04","activeKcal":512.0,"basalKcal":1834.0,"basalImputed":false,"watchKcal":2346.0,
          "factor":0.921,"calibrationStatus":"OK","expenditureKcal":2161.0,"intakeKcal":1904.0,"tracked":true,
          "deficitKcal":257.0,"projected":false,"expenditureAvg7":2210.0,"avg7Complete":true},
         {"date":"2026-10-05","activeKcal":400.0,"basalKcal":1830.0,"basalImputed":false,"watchKcal":2230.0,
          "factor":0.921,"calibrationStatus":"OK","expenditureKcal":2054.0,"intakeKcal":null,"tracked":false,
          "deficitKcal":null,"projected":false,"expenditureAvg7":2190.0,"avg7Complete":true},
         {"date":"2026-10-06","activeKcal":420.0,"basalKcal":1830.0,"basalImputed":false,"watchKcal":2250.0,
          "factor":0.921,"calibrationStatus":"OK","expenditureKcal":2072.0,"intakeKcal":2000.0,"tracked":true,
          "deficitKcal":72.0,"projected":false,"expenditureAvg7":2180.0,"avg7Complete":false},
         {"date":"2026-10-08","activeKcal":null,"basalKcal":null,"basalImputed":false,"watchKcal":null,
          "factor":1.0,"calibrationStatus":"TOO_FEW_TRACKED_DAYS","expenditureKcal":null,"intakeKcal":1800.0,
          "tracked":false,"deficitKcal":null,"projected":false,"expenditureAvg7":null,"avg7Complete":false}]
        """.utf8)
        let days = try APIClient.decoder().decode([EnergyDay].self, from: json)
        let expenditure = days.compactMap(\.expenditureAverage)
        XCTAssertEqual(expenditure.map(\.kcal), [2210, 2190, 2180], "ein Tag ohne Uhr hat keine Kurve")
        let runs = FoodChartData.expenditureRuns(expenditure)
        XCTAssertEqual(runs.map(\.complete), [true, false])
        XCTAssertEqual(runs[1].samples.first?.value, 2190, "der gestrichelte Teil setzt am letzten festen an")
        XCTAssertTrue(FoodChartData.weightValues([weightPoint(10, 4, avg7: 90)], series: .expenditure,
                                                 from: day(10, 1), to: day(10, 31)).isEmpty,
                      "der Verbrauch ist keine Gewichtsreihe")
    }
}
