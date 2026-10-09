import XCTest
@testable import Healthy

/// Ring, Texte und HRV-Kurve der Recovery. Gerechnet ist alles im Dienst;
/// hier geht es darum, dass die App es richtig hinstellt.
final class RecoveryTests: XCTestCase {

    private func day(_ dayOfMonth: Int, status: RecoveryStatus = .ok, score: Int? = 72,
                     band: RecoveryBand? = .green, hrv: Double? = 58,
                     normal: (Double, Double)? = (46.9, 52.6),
                     calibration: RecoveryCalibration? = RecoveryCalibration(nights: 60, required: 14)) -> RecoveryDay {
        var components: [RecoveryComponent] = []
        if let hrv {
            components.append(RecoveryComponent(key: .hrv, value: hrv, unit: "ms", baseline: 49.7, z: 1.12, weight: 0.5))
        }
        components.append(RecoveryComponent(key: .sleepingHeartRate, value: 49.2, unit: "bpm", baseline: 52,
                                            z: 1.85, weight: 0.25))
        components.append(RecoveryComponent(key: .sleep, value: 461, unit: "min", baseline: 448, z: 0.31, weight: 0.15))
        let trend = normal.map { HrvTrend(mean7Ms: 52.1, nights7: 6, normalLowMs: $0.0, normalHighMs: $0.1,
                                          status: .within) }
        return RecoveryDay(date: CalendarDate(year: 2026, month: 10, day: dayOfMonth), status: status,
                           score: score, band: band, composite: nil, hrvMethod: hrv == nil ? nil : .sdnn,
                           calibration: calibration, components: components, hrvTrend: trend)
    }

    // MARK: - Ring

    func testRingShowsScoreInTheColourOfTheBand() {
        let ring = RecoveryFormat.ring(day(9))
        XCTAssertEqual(ring.main, "72 %")
        XCTAssertEqual(ring.sub, "", "daneben steht ohnehin „Recovery“")
        XCTAssertEqual(ring.ratio, 0.72, accuracy: 1e-9)
        XCTAssertEqual(ring.tone, .good)
        XCTAssertEqual(RecoveryFormat.tone(.yellow), .warn)
        XCTAssertEqual(RecoveryFormat.tone(.red), .bad)
    }

    /// Beim Kalibrieren: wie viele Naechte schon da sind - „9/14", „Nächte".
    func testRingWhileCalibratingCountsTheNights() {
        let ring = RecoveryFormat.ring(day(9, status: .calibrating, score: nil, band: nil, normal: nil,
                                           calibration: RecoveryCalibration(nights: 9, required: 14)))
        XCTAssertEqual(ring.main, "9/14")
        XCTAssertEqual(ring.sub, "Nächte")
        XCTAssertEqual(ring.ratio, 9.0 / 14, accuracy: 1e-9)
        XCTAssertEqual(ring.tone, .neutral)
    }

    /// Ohne HRV oder ohne Nacht kein Score - ein Strich, der Rest bleibt sichtbar.
    func testRingWithoutScoreShowsADash() {
        let noHrv = RecoveryFormat.ring(day(9, status: .noHrv, score: nil, band: nil, hrv: nil, normal: nil))
        XCTAssertEqual(noHrv.main, "–")
        XCTAssertEqual(noHrv.ratio, 0)
        XCTAssertEqual(RecoveryFormat.ring(day(9, status: .noNight, score: nil, band: nil)).sub, "Keine Nacht")
        XCTAssertEqual(RecoveryFormat.ring(nil).main, "–")
    }

    // MARK: - Texte

    /// Die Zeile im Dashboard: „HRV 58 ms · RHF 49 · 7:41 h".
    func testSummaryLine() {
        XCTAssertEqual(RecoveryFormat.summaryLine(day(9)), "HRV 58 ms · RHF 49 · 7:41 h")
        XCTAssertEqual(RecoveryFormat.summaryLine(day(9, status: .noHrv, score: nil, band: nil, hrv: nil)),
                       "RHF 49 · 7:41 h", "ohne HRV steht der Rest trotzdem da")
    }

    func testComponentValuesAndBaselines() {
        XCTAssertEqual(RecoveryFormat.value(.hrv, 58.4, unit: "ms"), "58 ms")
        XCTAssertEqual(RecoveryFormat.value(.sleepingHeartRate, 51.2, unit: "bpm"), "51 bpm")
        XCTAssertEqual(RecoveryFormat.value(.sleep, 461, unit: "min"), "7:41 h")
        XCTAssertEqual(RecoveryFormat.value(.respiratoryRate, 14.1, unit: "/min"), "14,1 /min")
        XCTAssertEqual(RecoveryFormat.hoursMinutes(480), "8:00 h")
        XCTAssertEqual(RecoveryFormat.baseline(day(9).components[0]), "⌀ 50 ms")
        XCTAssertEqual(RecoveryFormat.label(.sleepingHeartRate), "RHF")
        XCTAssertEqual(RecoveryFormat.label(.respiratoryRate), "Atemfrequenz")
        XCTAssertEqual(RecoveryFormat.trend(day(9).hrvTrend), "⌀ 7 Nächte 52 ms")
    }

    // MARK: - HRV-Kurve

    /// Linie und Band reissen an Luecken ab; das Band gibt es nur an Tagen
    /// mit Score, die Linie an jedem Tag mit HRV.
    func testHrvLineAndBandBreakAtGaps() {
        let days = [day(1), day(2), day(3, status: .calibrating, score: nil, band: nil, normal: nil),
                    day(4), day(6), day(7, status: .noHrv, score: nil, band: nil, hrv: nil, normal: nil)]
        XCTAssertEqual(RecoveryChartData.hrvValues(days).count, 5)
        XCTAssertEqual(RecoveryChartData.hrvRuns(days).map(\.samples.count), [4, 1])
        XCTAssertEqual(RecoveryChartData.bandRuns(days).map(\.samples.count), [2, 1, 1],
                       "ohne Band am 3., Luecke am 5.")
    }

    func testDomainHoldsLineAndBand() {
        let domain = RecoveryChartData.domain([day(1, hrv: 40, normal: (45, 52)), day(2, hrv: 61)])
        XCTAssertLessThan(domain.lowerBound, 40)
        XCTAssertGreaterThan(domain.upperBound, 61)
        XCTAssertEqual(RecoveryChartData.domain([]), 20...80)
    }
}
