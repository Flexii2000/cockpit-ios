import XCTest
@testable import coHabit

/// kcal aus Healthy (seit 2026-10-01): eine Health-Metrik, deren Werte der
/// Dienst selbst holt - die App liest dafuer nichts aus Apple Health, kennt
/// aber die Einheit „kcal" und den Schalter fuer die Einwilligung.
@MainActor
final class KcalTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    /// Das Detail aus den Fixtures, mit kcal aus Healthy und Einwilligung.
    static let kcalDetail = Fixtures.streakDetail
        .replacingOccurrences(of: #""health":null"#, with: #""health":{"metric":"KCAL"}"#)
        .replacingOccurrences(of: #""metric":"STEPS","label":"Schritte""#,
                              with: #""metric":"KCAL","label":"kcal aus Healthy""#)
        .replacingOccurrences(of: #""shareText":"nur die Schrittzahl wird geteilt"}"#,
                              with: #""shareText":"nur die kcal des Tages werden geteilt","source":"HEALTHY"}"#)
        .replacingOccurrences(of: #""healthConsent":false"#, with: #""healthConsent":true"#)

    /// Dasselbe mit Schritten aus Apple Health.
    static let stepsDetail = Fixtures.streakDetail
        .replacingOccurrences(of: #""health":null"#, with: #""health":{"metric":"STEPS"}"#)
        .replacingOccurrences(of: #""healthConsent":false"#, with: #""healthConsent":true"#)

    func testHealthBlockKnowsWhereTheValuesComeFrom() throws {
        let kcal = try decode(CohabitDetail.self, Self.kcalDetail)
        XCTAssertEqual(kcal.config.health?.metric, "KCAL")
        XCTAssertEqual(kcal.health?.label, "kcal aus Healthy")
        XCTAssertEqual(kcal.health?.source, "HEALTHY")
        XCTAssertTrue(kcal.health?.isFromHealthy ?? false)
        // Ein Dienst ohne das Feld: wie bisher vom Geraet.
        let old = try decode(CohabitDetail.self, Fixtures.streakDetail)
        XCTAssertNil(old.health?.source)
        XCTAssertFalse(old.health?.isFromHealthy ?? true)
    }

    /// kcal wird ausdruecklich nicht aus Apple Health gelesen - und auch
    /// nicht abonniert, selbst mit Einwilligung.
    func testKcalIsNeverReadFromTheDevice() throws {
        XCTAssertFalse(CohabitHealthSync.readsFromDevice("KCAL"))
        for metric in ["STEPS", "RUNNING_DISTANCE", "WORKOUTS", "WORKOUT_MINUTES"] {
            XCTAssertTrue(CohabitHealthSync.readsFromDevice(metric), metric)
        }

        let sync = CohabitHealthSync.shared
        let kcal = try decode(CohabitDetail.self, Self.kcalDetail)
        defer { sync.remove(kcal.id) }
        sync.update(from: kcal)
        XCTAssertFalse(sync.subscriptions.contains { $0.cohabitId == kcal.id }, "kcal kommt nicht vom Geraet")

        let steps = try decode(CohabitDetail.self, Self.stepsDetail)
        sync.update(from: steps)
        XCTAssertEqual(sync.subscriptions.first { $0.cohabitId == steps.id }?.metric, "STEPS",
                       "Schritte mit Einwilligung werden weiter abonniert")
        // Wechselt dasselbe Co-Habit auf kcal, faellt das Abo weg.
        sync.update(from: kcal)
        XCTAssertFalse(sync.subscriptions.contains { $0.cohabitId == kcal.id })
    }

    /// „kcal" ueberall, wo Einheiten beschriftet werden, und ein Punkt ist
    /// dort ein Tausender („1.840 kcal").
    func testTheUnitIsLabelledAndParsed() {
        XCTAssertEqual(ValueEntrySheet.unitTitle("KCAL"), "kcal")
        XCTAssertEqual(ValueEntrySheet.number("1.840", unit: "KCAL"), 1840)
        XCTAssertEqual(ValueEntrySheet.number("1840", unit: "KCAL"), 1840)
        XCTAssertTrue(CohabitSettingsForm.units.contains { $0 == ("KCAL", "kcal") })
    }

    /// Im Formular: „kcal aus Healthy" als Health-Metrik, sie bringt die
    /// Einheit `KCAL` mit - und so geht sie an den Dienst.
    func testTheFormOffersKcalFromHealthy() throws {
        XCTAssertTrue(CohabitSettingsForm.metrics.contains { $0 == ("KCAL", "kcal aus Healthy") })
        XCTAssertEqual(CohabitSettingsForm.unit(forHealthMetric: "KCAL"), "KCAL")
        XCTAssertEqual(CohabitSettingsForm.unit(forHealthMetric: "RUNNING_DISTANCE"), "KM")
        XCTAssertEqual(CohabitSettingsForm.unit(forHealthMetric: "WORKOUTS"), "COUNT")

        var config = CohabitConfig.draft(.goal)
        config.health = .init(metric: "KCAL")
        config.tracking = .init(mode: "VALUE", unit: CohabitSettingsForm.unit(forHealthMetric: "KCAL"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(config)) as? [String: Any])
        XCTAssertEqual((body["health"] as? [String: Any])?["metric"] as? String, "KCAL")
        XCTAssertEqual((body["tracking"] as? [String: Any])?["unit"] as? String, "KCAL")
    }
}
