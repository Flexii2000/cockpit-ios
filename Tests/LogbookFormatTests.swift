import XCTest
@testable import Healthy

/// Die Effekte und Mengen als Text (Vertrag §4.1, §5). Nur Platzhalter-Namen -
/// das Repo ist oeffentlich.
final class LogbookFormatTests: XCTestCase {

    private func predictor(kind: PredictorKind = .binary, variant: PredictorVariant = .main,
                           unit: String? = nil, perUnit: Double = 1, effect: Double? = 8.12,
                           ci: (Double, Double)? = (3.2, 13.04), pAdjusted: Double? = 0.004,
                           hrv: Double? = nil, heart: Double? = nil,
                           yes: Int? = 41, no: Int? = 37, n: Int = 78,
                           status: PredictorStatus = .ok) -> Predictor {
        Predictor(key: "LOGBOOK:b-1", source: .logbook, sourceId: "b-1", name: "Verhalten A", kind: kind,
                  variant: variant, unitLabel: unit, perUnit: perUnit, effect: effect, ciLow: ci?.0,
                  ciHigh: ci?.1, p: 0.0004, pAdjusted: pAdjusted, hrvEffectPercent: hrv,
                  sleepingHeartRateEffectBpm: heart, nYes: yes, nNo: no, n: n,
                  meanYes: nil, meanNo: nil, status: status)
    }

    // MARK: - Effekte

    /// „Name  +8,1 %-Pkt **" und darunter „[+3,2; +13,0] · 41 ja · 37 nein".
    func testEffectRowOfAYesNoBehaviour() {
        let row = predictor()
        XCTAssertEqual(LogbookFormat.effectLine(row), "+8,1 %-Pkt **")
        XCTAssertEqual(LogbookFormat.detail(row), "[+3,2; +13,0] · 41 ja · 37 nein")
        XCTAssertNil(LogbookFormat.perUnit(row))
    }

    func testNegativeEffectsUseTheRealMinus() {
        let row = predictor(effect: -6.4, ci: (-10.9, -1.9), pAdjusted: 0.03)
        XCTAssertEqual(LogbookFormat.effectLine(row), "\u{2212}6,4 %-Pkt *")
        XCTAssertEqual(LogbookFormat.detail(row), "[\u{2212}10,9; \u{2212}1,9] · 41 ja · 37 nein")
    }

    /// Die Bausteine unter dem Effekt: „HRV +9 % · RHF −1,9 bpm" - HRV ganz,
    /// der Puls mit einer Stelle, beide mit Vorzeichen (Vertrag §4.2).
    func testComponentLineUnderTheEffect() {
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: 9.4, heart: -1.85)),
                       "HRV +9 % · RHF \u{2212}1,9 bpm")
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: -7.6, heart: 2.1)),
                       "HRV \u{2212}8 % · RHF +2,1 bpm")
    }

    /// Fehlt ein Baustein, steht der andere allein; fehlen beide, gibt es die
    /// Zeile nicht.
    func testComponentLineShowsOnlyWhatIsThere() {
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: -2.8)), "HRV \u{2212}3 %")
        XCTAssertEqual(LogbookFormat.components(predictor(heart: 0.4)), "RHF +0,4 bpm")
        XCTAssertNil(LogbookFormat.components(predictor()))
    }

    /// Was auf null rundet, ist null - ohne Vorzeichen, auch kein „−0".
    func testComponentLineRoundsToZeroWithoutSign() {
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: -0.4, heart: -0.04)), "HRV 0 % · RHF 0,0 bpm")
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: 0.49, heart: 0.04)), "HRV 0 % · RHF 0,0 bpm")
        XCTAssertEqual(LogbookFormat.components(predictor(hrv: 0.5, heart: 0.05)), "HRV +1 % · RHF +0,1 bpm")
    }

    /// Sterne nach dem Holm-korrigierten p - ohne Stern kein Befund.
    func testStarsFollowTheAdjustedP() {
        XCTAssertEqual(LogbookFormat.stars(0.0009), "***")
        XCTAssertEqual(LogbookFormat.stars(0.009), "**")
        XCTAssertEqual(LogbookFormat.stars(0.049), "*")
        XCTAssertEqual(LogbookFormat.stars(0.05), "")
        XCTAssertEqual(LogbookFormat.stars(nil), "")
        XCTAssertEqual(LogbookFormat.effectLine(predictor(pAdjusted: 0.3)), "+8,1 %-Pkt")
    }

    /// Mengen gelten je Schritt: „je 1.000 Schritte", bei der Dosis „je Stück".
    func testAmountsNameTheirStep() {
        let steps = predictor(kind: .amount, unit: "Schritte", perUnit: 1000, effect: 1.3, ci: (0.2, 2.4),
                              yes: nil, no: nil, n: 84)
        XCTAssertEqual(LogbookFormat.perUnit(steps), "je 1.000 Schritte")
        XCTAssertEqual(LogbookFormat.detail(steps), "[+0,2; +2,4] · 84 Tage")
        let dose = predictor(kind: .amount, variant: .dose, unit: "Stück", yes: nil, no: nil, n: 23)
        XCTAssertEqual(LogbookFormat.perUnit(dose), "je Stück")
    }

    /// Zu wenig Daten: wie weit es noch ist - „3/5 ja · 5/5 nein".
    func testNotEvaluatedShowsHowFarItIs() {
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(effect: nil, yes: 3, no: 5, n: 8, status: .tooFew)),
                       "3/5 ja · 5/5 nein")
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(effect: nil, yes: 12, no: 2, n: 14, status: .tooFew)),
                       "5/5 ja · 2/5 nein")
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(effect: nil, yes: 6, no: 6, n: 12, status: .tooFew)),
                       "5/5 ja · 5/5 nein · 12/14 Tage")
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(kind: .amount, effect: nil, yes: nil, no: nil, n: 9,
                                                            status: .tooFew)), "9/14 Tage")
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(kind: .amount, variant: .dose, effect: nil,
                                                            yes: nil, no: nil, n: 6, status: .tooFew)),
                       "6/10 Ja-Tage")
        XCTAssertEqual(LogbookFormat.notEvaluated(predictor(status: .notSeparable)), "fällt aufs Wochenende")
    }

    // MARK: - Mengen

    func testAmountsWithGermanComma() {
        XCTAssertEqual(LogbookFormat.amount(2), "2")
        XCTAssertEqual(LogbookFormat.amount(1.5), "1,5")
        XCTAssertEqual(LogbookFormat.amount(0.25), "0,25")
        XCTAssertEqual(LogbookFormat.parseAmount("1,5"), 1.5)
        XCTAssertEqual(LogbookFormat.parseAmount(" 2 "), 2)
        XCTAssertEqual(LogbookFormat.parseAmount("0.5"), 0.5)
        XCTAssertNil(LogbookFormat.parseAmount(""))
        XCTAssertEqual(LogbookFormat.parseAmount("0"), 0, "0 ist eine Antwort, offen ist etwas anderes")
        XCTAssertNil(LogbookFormat.parseAmount("-1"))
        XCTAssertNil(LogbookFormat.parseAmount("10001"), "mehr nimmt der Dienst nicht")
        XCTAssertNil(LogbookFormat.parseAmount("zwei"))
    }
}
