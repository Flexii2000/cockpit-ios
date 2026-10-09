import XCTest
@testable import Healthy

/// Die Formate aus dem Vertrag (`weight-app/docs/HEALTHY-CONTRACT.md` §5) -
/// auf allen Oberflaechen gleich, deshalb Zeichen fuer Zeichen geprueft.
final class EnergyFormatTests: XCTestCase {

    private func day(expenditure: Double?, watch: Double? = nil, factor: Double = 1,
                     deficit: Double? = nil, projected: Bool = false) -> EnergyDay {
        EnergyDay(date: CalendarDate(year: 2026, month: 10, day: 9), activeKcal: nil, basalKcal: nil,
                  basalImputed: false, watchKcal: watch, factor: factor,
                  calibrationStatus: factor == 1 ? .tooFewTrackedDays : .ok,
                  expenditureKcal: expenditure, intakeKcal: nil, tracked: deficit != nil,
                  deficitKcal: deficit, projected: projected, expenditureAvg7: nil, avg7Complete: false)
    }

    /// Deutsch, egal wie das Geraet eingestellt ist; negative mit U+2212.
    func testGermanNumbers() {
        XCTAssertEqual(GermanNumber.string(2610), "2.610")
        XCTAssertEqual(GermanNumber.string(2610.4), "2.610")
        XCTAssertEqual(GermanNumber.string(1_234_567), "1.234.567")
        XCTAssertEqual(GermanNumber.string(-120), "\u{2212}120")
        XCTAssertEqual(GermanNumber.string(8.06, decimals: 1, signed: true), "+8,1")
        XCTAssertEqual(GermanNumber.string(-2.04, decimals: 1, signed: true), "\u{2212}2,0")
        XCTAssertEqual(GermanNumber.string(-0.04, decimals: 1, signed: true), "0,0", "keine „−0,0“")
        XCTAssertEqual(GermanNumber.string(14.25, decimals: 1), "14,3")
    }

    /// Die Korrektur der Uhr in ganzen Prozent.
    func testCalibrationIsTheCorrectionInWholePercent() {
        XCTAssertEqual(EnergyFormat.calibration(0.921), "\u{2212}8 %")
        XCTAssertEqual(EnergyFormat.calibration(1.03), "+3 %")
        XCTAssertEqual(EnergyFormat.calibration(1.0), "0 %")
        XCTAssertEqual(EnergyFormat.calibration(0.996), "0 %")
    }

    /// „Verbrauch [≈ ]2.610 kcal · Uhr 2.840 · −8 %" - der Teil mit der Uhr
    /// nur, wenn sie etwas gemeldet hat und korrigiert wurde.
    func testExpenditureLine() {
        let today = day(expenditure: 2612.8, watch: 2840, factor: 0.92, projected: true)
        XCTAssertEqual(EnergyFormat.expenditureLine(today),
                       "Verbrauch ≈ 2.613 kcal · Uhr 2.840 · \u{2212}8 %")
        XCTAssertEqual(EnergyFormat.watch(today), "Uhr 2.840 · \u{2212}8 %")

        let uncalibrated = day(expenditure: 2346, watch: 2346, factor: 1)
        XCTAssertEqual(EnergyFormat.expenditureLine(uncalibrated), "Verbrauch 2.346 kcal")
        XCTAssertNil(EnergyFormat.watch(uncalibrated))

        XCTAssertNil(EnergyFormat.expenditureLine(day(expenditure: nil)), "ohne Uhr keine Zeile")
    }

    /// „Defizit [≈ ]460 kcal" bzw. „Überschuss [≈ ]120 kcal" - ohne Vorzeichen,
    /// das Wort sagt die Richtung.
    func testBalanceLine() {
        XCTAssertEqual(EnergyFormat.balanceLine(day(expenditure: 2610, deficit: 460.4, projected: true)),
                       "Defizit ≈ 460 kcal")
        XCTAssertEqual(EnergyFormat.balanceLine(day(expenditure: 2610, deficit: -120)), "Überschuss 120 kcal")
        XCTAssertEqual(EnergyFormat.balanceLine(day(expenditure: 2610, deficit: -0.3)), "Defizit 0 kcal")
        XCTAssertNil(EnergyFormat.balanceLine(day(expenditure: 2610)), "nicht getrackt: kein Defizit")
    }
}
