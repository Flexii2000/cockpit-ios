import XCTest
@testable import Healthy

/// Die Energie-Karte im Dashboard (Vertrag §5, „Balken + Woche"): was
/// gezeichnet wird, fuer jeden Sonderfall des Vertrags - der Simulator
/// bekommt keine Health-Daten, im Bild liesse sich das nie nachstellen.
final class EnergyCardModelTests: XCTestCase {

    /// Ein Freitag.
    private let today = CalendarDate(year: 2026, month: 10, day: 9)

    private func energy(_ offset: Int, deficit: Double?, intake: Double? = nil,
                        expenditure: Double? = 2840, projected: Bool = false) -> EnergyDay {
        EnergyDay(date: today.adding(days: -offset), activeKcal: nil, basalKcal: nil, basalImputed: false,
                  watchKcal: expenditure, factor: 1, calibrationStatus: .ok, expenditureKcal: expenditure,
                  intakeKcal: intake, tracked: deficit != nil, deficitKcal: deficit, projected: projected,
                  expenditureAvg7: nil, deficitAvg7: nil, avg7Complete: false)
    }

    private func summary(today day: EnergyDay?, deficit7: Double? = 312) -> EnergySummary {
        EnergySummary(today: day, deficit7: deficit7, deficit7Days: 6, expenditure7: 2236, expenditure7Days: 7,
                      calibration: Calibration(status: .ok, factor: 1, rawFactor: 1, windowFrom: nil,
                                               windowTo: nil, measuredKcal: nil, measuredSeKcal: nil,
                                               watchKcal: nil, intakeKcal: nil, weightSlopeKgPerWeek: nil,
                                               trackedDays: 25, weightDays: 27, watchDays: 28),
                      sources: ["food": "OK"])
    }

    // MARK: - Kopfzeile und Bilanzbalken

    /// Defizit: gelb bis „gegessen", die Luecke bis zum Verbrauch in
    /// Defizit-Farbe, die Marke am Ende - der Verbrauch ist das Laengere.
    func testDeficit() throws {
        let day = energy(0, deficit: 690, intake: 2150, projected: true)
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: day), week: [day], today: today))
        XCTAssertEqual(model.headline,
                       EnergyCardModel.Headline(word: "Defizit", amount: "≈ 690 kcal", isSurplus: false))
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.eaten, 2150 / 2840, accuracy: 1e-9)
        XCTAssertEqual(bar.gap, 690 / 2840, accuracy: 1e-9)
        XCTAssertEqual(bar.overflow, 0)
        XCTAssertEqual(bar.mark, 1)
        XCTAssertEqual(bar.eaten + bar.gap + bar.overflow, 1, accuracy: 1e-9, "der Balken ist ganz gefuellt")
        XCTAssertEqual(bar.eatenLabel, "gegessen 2.150")
        XCTAssertEqual(bar.expenditureLabel, "Verbrauch ≈ 2.840")
    }

    /// Ueberschuss: gelb bis zum Verbrauch, der Rest in Ueberschuss-Farbe -
    /// jetzt ist „gegessen" das Laengere und die Marke steht davor.
    func testSurplus() throws {
        let day = energy(0, deficit: -300, intake: 2900, expenditure: 2600, projected: true)
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: day), week: [day], today: today))
        XCTAssertEqual(model.headline,
                       EnergyCardModel.Headline(word: "Überschuss", amount: "≈ 300 kcal", isSurplus: true))
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.eaten, 2600 / 2900, accuracy: 1e-9)
        XCTAssertEqual(bar.gap, 0)
        XCTAssertEqual(bar.overflow, 300 / 2900, accuracy: 1e-9)
        XCTAssertEqual(bar.mark, 2600 / 2900, accuracy: 1e-9)
        XCTAssertEqual(bar.eatenLabel, "gegessen 2.900")
    }

    /// Heute noch nichts gegessen: kein Gelb, die ganze Laenge ist Defizit,
    /// und unten steht 0 - nicht nichts.
    func testNothingEatenYet() throws {
        let day = energy(0, deficit: 2840, intake: nil, projected: true)
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: day), week: [day], today: today))
        let bar = try XCTUnwrap(model.bar)
        XCTAssertEqual(bar.eaten, 0)
        XCTAssertEqual(bar.gap, 1)
        XCTAssertEqual(bar.mark, 1)
        XCTAssertEqual(bar.eatenLabel, "gegessen 0")
        XCTAssertEqual(model.headline?.amount, "≈ 2.840 kcal")
    }

    /// Ohne Defizit heute (nicht getrackt, Kalorienzaehler weg) fehlen Kopfzeile
    /// und Balken - die Woche bleibt, wenn sie Werte hat.
    func testWithoutDeficitTodayOnlyTheWeekRemains() throws {
        let day = energy(0, deficit: nil, intake: 900, projected: true)
        let week = [energy(2, deficit: 400), day]
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: day), week: week, today: today))
        XCTAssertNil(model.headline)
        XCTAssertNil(model.bar)
        XCTAssertNotNil(model.week)
    }

    /// Die Prognose von heute: „≈" vor den Zahlen, ihr Balken in der Woche
    /// blasser. Ein vergangener Tag ist keine Prognose.
    func testTodayIsAProjection() throws {
        let day = energy(0, deficit: 690, intake: 2150, projected: true)
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: day),
                                                  week: [energy(1, deficit: 500), day], today: today))
        XCTAssertTrue(model.headline?.amount.hasPrefix("≈ ") ?? false)
        XCTAssertTrue(model.bar?.expenditureLabel.contains("≈") ?? false)
        let bars = try XCTUnwrap(model.week?.bars)
        XCTAssertEqual(bars.last?.isProjected, true)
        XCTAssertEqual(bars[5].isProjected, false)
    }

    // MARK: - Woche

    /// Sieben Tage D−6 … heute; ein Tag ohne Wert bleibt leer, ein
    /// Ueberschuss geht nach unten. Beide Richtungen an einer Skala: der
    /// groesste Betrag jeder Richtung reicht an ihren Rand.
    func testWeekWithSurplusAndDayWithoutValue() throws {
        let week = [energy(6, deficit: 400), energy(5, deficit: nil), energy(4, deficit: 600),
                    energy(3, deficit: -300), energy(2, deficit: 200), energy(1, deficit: 500),
                    energy(0, deficit: 690, intake: 2150, projected: true)]
        let model = try XCTUnwrap(EnergyCardModel(summary: summary(today: week.last), week: week,
                                                  today: today))
        let days = try XCTUnwrap(model.week)
        XCTAssertEqual(days.bars.map(\.label), ["Sa", "So", "Mo", "Di", "Mi", "Do", "heute"])
        XCTAssertEqual(days.zeroLine, 690.0 / 990, accuracy: 1e-9)
        XCTAssertNil(days.bars[1].height, "ein Tag ohne Wert: kein Balken, keine Null")
        XCTAssertEqual(days.bars[3].isSurplus, true)
        XCTAssertEqual(days.bars[3].height ?? 0, 300.0 / 990, accuracy: 1e-9)
        XCTAssertEqual(days.bars[6].height ?? 0, 690.0 / 990, accuracy: 1e-9)
        // Das groesste Defizit reicht von der Nulllinie bis oben, der groesste
        // Ueberschuss bis unten.
        XCTAssertEqual(days.bars[6].height ?? 0, days.zeroLine, accuracy: 1e-9)
        XCTAssertEqual((days.bars[3].height ?? 0) + days.zeroLine, 1, accuracy: 1e-9)
        XCTAssertEqual(days.average, "312 kcal")
    }

    /// Ohne Ueberschuss liegt die Nulllinie unten, ohne Defizit oben.
    func testZeroLineMovesToTheEdgeWithOneDirection() throws {
        let deficits = [energy(3, deficit: 250), energy(1, deficit: 500)]
        let up = try XCTUnwrap(EnergyCardModel.week(deficits, today: today, average: 300))
        XCTAssertEqual(up.zeroLine, 1)
        XCTAssertEqual(up.bars[6 - 1].height, 1)
        XCTAssertEqual(up.bars[6 - 3].height, 0.5)

        let surpluses = [energy(2, deficit: -100), energy(1, deficit: -400)]
        let down = try XCTUnwrap(EnergyCardModel.week(surpluses, today: today, average: -250))
        XCTAssertEqual(down.zeroLine, 0)
        XCTAssertEqual(down.bars[6 - 1].height, 1)
        XCTAssertEqual(down.bars[6 - 2].height, 0.25)
        XCTAssertTrue(down.bars[6 - 2].isSurplus)
        XCTAssertEqual(down.average, "\u{2212}250 kcal", "Ueberschuss mit echtem Minus")
    }

    /// Was auf 0 rundet, ist kein Ueberschuss - wie beim Wort der Kopfzeile.
    func testRoundedZeroIsNoSurplus() throws {
        let week = [energy(2, deficit: -0.3), energy(1, deficit: 400)]
        let days = try XCTUnwrap(EnergyCardModel.week(week, today: today, average: nil))
        XCTAssertFalse(days.bars[4].isSurplus)
        XCTAssertEqual(days.bars[4].height, 0)
        XCTAssertEqual(days.zeroLine, 1)
        XCTAssertEqual(days.average, "–", "ohne deficit7 ein Strich")
    }

    /// Eine Woche ohne einen einzigen Wert fehlt - und ohne Defizit heute
    /// dazu die ganze Karte.
    func testEmptyWeek() throws {
        let untracked = [energy(3, deficit: nil, intake: 1200), energy(1, deficit: nil, intake: 900)]
        XCTAssertNil(EnergyCardModel.week(untracked, today: today, average: nil))
        XCTAssertNil(EnergyCardModel.week([], today: today, average: 312))

        let day = energy(0, deficit: 690, intake: 2150, projected: true)
        let onlyToday = try XCTUnwrap(EnergyCardModel(summary: summary(today: day), week: [], today: today))
        XCTAssertNil(onlyToday.week, "faellt die Woche aus, bleiben Kopfzeile und Balken")
        XCTAssertNotNil(onlyToday.bar)

        XCTAssertNil(EnergyCardModel(summary: summary(today: nil), week: untracked, today: today))
        XCTAssertNil(EnergyCardModel(summary: nil, week: [], today: today))
    }

    /// Faellt nur die Summary aus, kommt heute aus der Woche - „⌀ 7 T" ist
    /// dann unbekannt.
    func testTodayFromTheWeekWithoutSummary() throws {
        let day = energy(0, deficit: 690, intake: 2150, projected: true)
        let model = try XCTUnwrap(EnergyCardModel(summary: nil, week: [energy(1, deficit: 500), day],
                                                  today: today))
        XCTAssertEqual(model.headline?.word, "Defizit")
        XCTAssertNotNil(model.bar)
        XCTAssertEqual(model.week?.average, "–")
    }

    /// Ueber einen Monatswechsel: die Wochentage folgen dem Kalender.
    func testWeekdayLabels() {
        let monday = CalendarDate(year: 2026, month: 11, day: 2)
        let labels = (-6...0).map { EnergyCardModel.weekdayLabel(monday.adding(days: $0), today: monday) }
        XCTAssertEqual(labels, ["Di", "Mi", "Do", "Fr", "Sa", "So", "heute"])
    }
}
