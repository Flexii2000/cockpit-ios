import XCTest
@testable import Healthy

/// Die beiden Diagramme im Strain-Fenster (Vertrag §5): Balken, Stufenlinie
/// des Ziels, die Linien „Akut“ und „Gewohnt“, die Flaeche dazwischen und die
/// Recovery-Punkte. Gezeichnet wird in `StrainSheet`; was gezeichnet wird,
/// steht hier.
final class StrainChartDataTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ day: Int) -> CalendarDate { CalendarDate(year: 2026, month: 11, day: day) }

    private func day(_ number: Int, strain: Double? = nil, target: Double? = nil, acute: Double? = nil,
                     chronic: Double? = nil, recovery: RecoveryBand? = nil, partial: Bool = false) -> StrainDay {
        StrainDay(date: date(number), status: strain == nil ? .noData : .ok, partial: partial, strain: strain,
                  targetStrain: target, acuteLoad: acute, chronicLoad: chronic,
                  recoveryScore: recovery == nil ? nil : 60, recoveryBand: recovery)
    }

    // MARK: - Strain

    /// Je Tag mit Histogramm ein Balken; ein Tag ohne fehlt. Heute ist
    /// markiert - der Tag laeuft noch.
    func testBarsOnlyForDaysWithAHistogram() {
        let bars = StrainChartData.bars([day(3, strain: 10.5), day(1, strain: 4.2), day(2),
                                         day(4, strain: 12.4, partial: true)], in: berlin)
        XCTAssertEqual(bars.map(\.day), [date(1), date(3), date(4)], "aufsteigend, der 2. fehlt")
        XCTAssertEqual(bars.map(\.strain), [4.2, 10.5, 12.4])
        XCTAssertEqual(bars.map(\.isPartial), [false, false, true])
        XCTAssertEqual(bars.first?.date, date(1).startOfDay(in: berlin))
    }

    /// Das Ziel gehoert zum Morgen: es laeuft ueber einen Tag ohne Histogramm
    /// weiter. Nur wo es keins gibt, reisst die Linie ab.
    func testTargetRunsAcrossDaysWithoutAHistogram() {
        let runs = StrainChartData.targetRuns([
            day(1, strain: 9, target: 12.1), day(2, target: 12.4), day(3, strain: 11, target: 12.0),
            day(4, strain: 8), day(5, strain: 7, target: 11.5),
        ], in: berlin)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].samples.map(\.value), [12.1, 12.4, 12.0])
        XCTAssertEqual(runs[1].samples.map(\.value), [11.5])
        XCTAssertTrue(runs[1].isSingle, "eine Stufe allein - das Fenster zeichnet sie als Strich")
    }

    // MARK: - Form

    /// „Akut“ und „Gewohnt“ als eigene Linien, an jeder Luecke getrennt.
    func testAcuteAndChronicRuns() {
        let days = [day(1, acute: 110, chronic: 100), day(2, acute: 118, chronic: 101),
                    day(4, acute: 96, chronic: 102)]
        let acute = StrainChartData.acuteRuns(days, in: berlin)
        XCTAssertEqual(acute.map { $0.samples.map(\.value) }, [[110, 118], [96]])
        XCTAssertEqual(StrainChartData.chronicRuns(days, in: berlin).map { $0.samples.map(\.value) },
                       [[100, 101], [102]])
        XCTAssertNotEqual(acute.first?.id, StrainChartData.chronicRuns(days, in: berlin).first?.id)
    }

    /// Die Flaeche wechselt am Schnittpunkt die Farbe: wo Akut ueber Gewohnt
    /// liegt, „über Ziel“ (`isDeficit`), sonst die Strain-Farbe.
    func testFormAreaSwitchesColourWhereTheLinesCross() throws {
        let segments = StrainChartData.formSegments([
            day(1, acute: 120, chronic: 100), day(2, acute: 110, chronic: 100),
            day(3, acute: 90, chronic: 100), day(4, acute: 80, chronic: 100),
        ], in: berlin)
        XCTAssertEqual(segments.map(\.isDeficit), [true, false])
        // Zwischen dem 2. (+10) und dem 3. (−10) schneiden sie sich in der Mitte.
        let crossing = try XCTUnwrap(segments.first?.points.last)
        XCTAssertEqual(crossing.date, date(2).startOfDay(in: berlin).addingTimeInterval(43_200))
        XCTAssertEqual(crossing.expenditure, 100, accuracy: 1e-9)
        XCTAssertEqual(crossing.intake, 100, accuracy: 1e-9)
        XCTAssertEqual(segments.last?.points.first, crossing, "beide Stuecke enden am selben Punkt")
    }

    /// Ohne eine der beiden Linien gibt es an dem Tag keine Flaeche.
    func testFormAreaNeedsBothLines() {
        XCTAssertTrue(StrainChartData.formSegments([day(1, acute: 120), day(2, acute: 110)], in: berlin).isEmpty)
    }

    /// Je Tag mit Recovery ein Punkt auf der Akut-Linie, in der Farbe ihres
    /// Bands - ohne Recovery oder ohne Akut keiner.
    func testRecoveryDotsSitOnTheAcuteLine() {
        let dots = StrainChartData.recoveryDots([
            day(1, acute: 110, chronic: 100, recovery: .green), day(2, acute: 118, chronic: 101),
            day(3, chronic: 100, recovery: .red), day(4, acute: 96, chronic: 102, recovery: .yellow),
            day(5, acute: 90, chronic: 102, recovery: .unknown),
        ], in: berlin)
        XCTAssertEqual(dots.map(\.value), [110, 96])
        XCTAssertEqual(dots.map(\.band), [.green, .yellow])
        XCTAssertEqual(dots.first?.date, date(1).startOfDay(in: berlin))
    }

    /// Die y-Achse beginnt bei 0 und endet auf runden 50 ueber dem groessten
    /// Wert - mindestens bei 100.
    func testLoadDomain() {
        XCTAssertEqual(StrainChartData.loadDomain([day(1, acute: 118, chronic: 101)]), 0...150)
        XCTAssertEqual(StrainChartData.loadDomain([day(1, acute: 40, chronic: 35)]), 0...100)
        XCTAssertEqual(StrainChartData.loadDomain([]), 0...100)
    }

    // MARK: - Antippen

    /// Waehlbar ist jeder Tag mit einem Wert in einem der Diagramme.
    func testSelectableDays() {
        let days = [day(1, strain: 9), day(2), day(3, target: 12), day(4, acute: 100), day(5, chronic: 90)]
        XCTAssertEqual(StrainChartData.selectableDays(days), [date(1), date(3), date(4), date(5)])
    }

    /// Im Verlauf `Strain 12,4` und `Ziel 14,1` - was es davon gibt; in der
    /// Form-Kurve `Akut 118` und `Gewohnt 111`.
    func testCallouts() {
        let full = day(1, strain: 12.4, target: 14.1, acute: 118.2, chronic: 110.5)
        XCTAssertEqual(StrainChartData.strainCallout(full).map(\.label), ["Strain", "Ziel"])
        XCTAssertEqual(StrainChartData.strainCallout(full).map(\.value), ["12,4", "14,1"])
        XCTAssertEqual(StrainChartData.formCallout(full).map(\.label), ["Akut", "Gewohnt"])
        XCTAssertEqual(StrainChartData.formCallout(full).map(\.value), ["118", "111"])

        let quiet = day(2, target: 13.2)
        XCTAssertEqual(StrainChartData.strainCallout(quiet).map(\.label), ["Ziel"])
        XCTAssertTrue(StrainChartData.formCallout(quiet).isEmpty)
    }

    // MARK: - Zeitraum

    /// Die vier Zeitraeume aus dem Vertrag, gemerkt - und eine unbekannte
    /// Merkzahl faellt auf sechs Wochen zurueck.
    func testRangesAndTheirMemory() throws {
        XCTAssertEqual(StrainRange.allCases.map(\.rawValue), [42, 90, 180, 365])
        XCTAssertEqual(StrainRange.allCases.map(\.title), ["6 Wo.", "3 Mon.", "6 Mon.", "1 Jahr"])
        let name = "strain-range-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        XCTAssertEqual(StrainRange.load(from: defaults), .sixWeeks)
        StrainRange.year.save(in: defaults)
        XCTAssertEqual(StrainRange.load(from: defaults), .year)
        defaults.set(77, forKey: StrainRange.key)
        XCTAssertEqual(StrainRange.load(from: defaults), .sixWeeks)
    }
}
