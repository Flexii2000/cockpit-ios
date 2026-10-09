import XCTest
@testable import Healthy

/// Die Effekte als Text (Vertrag §4.1, §5) und was die Logbook-Seite zum
/// Dienst schickt. Nur Platzhalter-Namen - das Repo ist oeffentlich.
final class LogbookFormatTests: XCTestCase {

    private func predictor(kind: PredictorKind = .binary, variant: PredictorVariant = .main,
                           unit: String? = nil, perUnit: Double = 1, effect: Double? = 8.12,
                           ci: (Double, Double)? = (3.2, 13.04), pAdjusted: Double? = 0.004,
                           yes: Int? = 41, no: Int? = 37, n: Int = 78,
                           status: PredictorStatus = .ok) -> Predictor {
        Predictor(key: "LOGBOOK:b-1", source: .logbook, sourceId: "b-1", name: "Verhalten A", kind: kind,
                  variant: variant, unitLabel: unit, perUnit: perUnit, effect: effect, ciLow: ci?.0,
                  ciHigh: ci?.1, p: 0.0004, pAdjusted: pAdjusted, nYes: yes, nNo: no, n: n,
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
        XCTAssertNil(LogbookFormat.parseAmount("0"), "eine Menge ist mehr als nichts")
        XCTAssertNil(LogbookFormat.parseAmount("10001"), "mehr nimmt der Dienst nicht")
        XCTAssertNil(LogbookFormat.parseAmount("zwei"))
    }

    // MARK: - Entwurf

    private let behaviors = [
        Behavior(id: "b-1", name: "Verhalten A", unit: nil, createdAt: nil, archived: false),
        Behavior(id: "b-2", name: "Verhalten B", unit: "Stück", createdAt: nil, archived: false),
        Behavior(id: "b-3", name: "Verhalten C", unit: nil, createdAt: nil, archived: false),
    ]

    /// Ein gespeicherter Tag zeigt sich wie gespeichert; ein offener alles aus.
    func testEntriesFollowTheSavedDay() {
        let saved = LogbookDraft.entries(for: behaviors, values: ["b-1": 1, "b-2": 1.5, "b-3": 0])
        XCTAssertEqual(saved["b-1"], LogbookEntry(isOn: true, amount: ""))
        XCTAssertEqual(saved["b-2"], LogbookEntry(isOn: true, amount: "1,5"))
        XCTAssertEqual(saved["b-3"], LogbookEntry(isOn: false, amount: ""))
        XCTAssertEqual(LogbookDraft.entries(for: behaviors, values: nil)["b-2"],
                       LogbookEntry(isOn: false, amount: ""))
    }

    /// Geschickt wird nur, was an ist - der Rest wird beim Dienst „nein".
    func testValuesSendOnlyWhatIsOn() {
        let entries = ["b-1": LogbookEntry(isOn: true, amount: ""),
                       "b-2": LogbookEntry(isOn: true, amount: "2,5"),
                       "b-3": LogbookEntry(isOn: false, amount: "")]
        XCTAssertEqual(LogbookDraft.values(entries, behaviors: behaviors), ["b-1": 1, "b-2": 2.5])
        XCTAssertEqual(LogbookDraft.values([:], behaviors: behaviors), [:], "lauter nein ist auch ein Tag")
    }

    /// Eine angetippte Menge ohne Zahl: nicht speichern, statt eine zu erfinden.
    func testMissingAmountBlocksSaving() {
        let entries = ["b-2": LogbookEntry(isOn: true, amount: "")]
        XCTAssertNil(LogbookDraft.values(entries, behaviors: behaviors))
        let off = ["b-2": LogbookEntry(isOn: false, amount: "")]
        XCTAssertEqual(LogbookDraft.values(off, behaviors: behaviors), [:])
    }
}
