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
                  deficitKcal: deficit, projected: projected, expenditureAvg7: nil, deficitAvg7: nil,
                  avg7Complete: false)
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

    /// Die Energie-Karte im Dashboard: Wort und Betrag getrennt (nur der
    /// Betrag ist farbig), unter dem Balken „gegessen …" und „Verbrauch ≈ …"
    /// ohne Einheit.
    func testEnergyCardTexts() {
        let today = EnergyDay(date: CalendarDate(year: 2026, month: 10, day: 9), activeKcal: nil,
                              basalKcal: nil, basalImputed: false, watchKcal: 3087, factor: 0.92,
                              calibrationStatus: .ok, expenditureKcal: 2840, intakeKcal: 2150, tracked: true,
                              deficitKcal: 690, projected: true, expenditureAvg7: nil, deficitAvg7: nil,
                              avg7Complete: false)
        let balance = EnergyFormat.balance(today)
        XCTAssertEqual(balance?.word, "Defizit")
        XCTAssertEqual(balance?.amount, "≈ 690 kcal")
        XCTAssertEqual(balance?.isSurplus, false)
        XCTAssertEqual(EnergyFormat.eaten(today), "gegessen 2.150")
        XCTAssertEqual(EnergyFormat.expenditureShort(today), "Verbrauch ≈ 2.840")

        // Heute noch nichts gegessen: null, und das Defizit ist der Verbrauch.
        let fasting = day(expenditure: 2840, watch: 3087, factor: 0.92, deficit: 2840, projected: true)
        XCTAssertEqual(EnergyFormat.eaten(fasting), "gegessen 0")
        XCTAssertEqual(EnergyFormat.balance(fasting)?.amount, "≈ 2.840 kcal")

        let surplus = EnergyFormat.balance(day(expenditure: 2600, deficit: -300.4))
        XCTAssertEqual(surplus?.word, "Überschuss")
        XCTAssertEqual(surplus?.amount, "300 kcal", "ohne Vorzeichen - das Wort sagt die Richtung")
        XCTAssertEqual(surplus?.isSurplus, true)

        // Das Wort nach dem gerundeten Wert: −0,3 ist kein Ueberschuss.
        let even = EnergyFormat.balance(day(expenditure: 2610, deficit: -0.3))
        XCTAssertEqual(even?.word, "Defizit")
        XCTAssertEqual(even?.amount, "0 kcal")
        XCTAssertEqual(even?.isSurplus, false)
        XCTAssertNil(EnergyFormat.balance(day(expenditure: 2610)), "nicht getrackt: kein Defizit")
    }
}
