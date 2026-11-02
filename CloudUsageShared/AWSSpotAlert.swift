import Foundation

/// Wann die CloudUsageBar „Spot frei“ meldet (Felix, 02.11.): das LLM läuft auf
/// On-Demand, und für denselben Typ ist Spot wieder zu haben - einmal je Instanz.
/// Hier statt in der Mac-App, damit die Tests (VaultTests) es prüfen können.
enum AWSSpotAlert {

    struct Alert: Equatable, Sendable {
        let instanceID: String
        let title: String
        let body: String
    }

    /// Ältere Spot-Zahlen lösen nichts aus - dann kam der Dienst nicht bei AWS durch.
    static let maxAge: TimeInterval = 5 * 60

    static func due(_ usage: AWSUsage, sent: Set<String>, now: Date = Date()) -> Alert? {
        guard let spot = usage.spot, let checkedAt = spot.checkedAt,
              now.timeIntervalSince(checkedAt) < maxAge else { return nil }
        for instance in usage.running
        where instance.category == AWSCategoryKey.llm.rawValue && !instance.isSpot && !sent.contains(instance.id) {
            guard let type = spot.types.first(where: { $0.type == instance.type }),
                  type.estimate > 0, type.isLaunchable else { continue }
            var body = "\(type.type) · \(CloudUsageFormat.spotCount(type.estimate, max: spot.maxCount))"
            if let price = type.pricePerHour {
                body += " · \(CloudUsageFormat.perHour(price))"
                if let onDemand = instance.pricePerHour {
                    body += " statt \(CloudUsageFormat.perHour(onDemand))"
                }
            }
            return Alert(instanceID: instance.id, title: "LLM: Spot frei", body: body)
        }
        return nil
    }
}
