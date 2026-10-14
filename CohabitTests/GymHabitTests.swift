import XCTest
@testable import coHabit

/// Gym aus Healthy (seit 2026-10-14): wie die kcal holt der Dienst die Tage mit
/// beendetem Training selbst - nur als Serie, und ein Haken ohne Wert.
@MainActor
final class GymHabitTests: XCTestCase {

    static let gymDetail = KcalTests.kcalDetail
        .replacingOccurrences(of: #""health":{"metric":"KCAL"}"#, with: #""health":{"metric":"GYM"}"#)
        .replacingOccurrences(of: #""metric":"KCAL","label":"kcal aus Healthy""#,
                              with: #""metric":"GYM","label":"Gym aus Healthy""#)

    func testOnlyAStreakOffersGym() {
        XCTAssertTrue(CohabitSettingsForm.metrics(for: .streak).contains { $0.0 == "GYM" })
        for type in [CohabitType.goal, .challenge] {
            XCTAssertFalse(CohabitSettingsForm.metrics(for: type).contains { $0.0 == "GYM" }, "\(type)")
        }
    }

    func testGymComesFromHealthyNotFromTheDevice() throws {
        XCTAssertFalse(CohabitHealthSync.readsFromDevice("GYM"))
        let gym = try APIClient.decoder().decode(CohabitDetail.self, from: Fixtures.data(Self.gymDetail))
        XCTAssertEqual(gym.config.health?.metric, "GYM")
        XCTAssertEqual(gym.health?.label, "Gym aus Healthy")
        XCTAssertTrue(gym.health?.isFromHealthy ?? false)

        let sync = CohabitHealthSync.shared
        defer { sync.remove(gym.id) }
        sync.update(from: gym)
        XCTAssertFalse(sync.subscriptions.contains { $0.cohabitId == gym.id }, "Gym kommt nicht vom Geraet")
    }
}
