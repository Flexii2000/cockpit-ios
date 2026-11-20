import Foundation
import HealthKit

/// Die Schritte von heute aus Health auf der Uhr - fuer den Schritte-Ring der
/// grossen Komplikation (20.11.). Die Uhr schreibt ihre Schritte laufend
/// hinein; der Spiegel des iPhones (`StepsMirror`) waere nur so frisch wie das
/// letzte Oeffnen von Healthy.
///
/// Fragen darf nur die Uhr-App (`requestAuthorization`); die Komplikation liest
/// nur, mit derselben Erlaubnis.
enum WatchStepCount {

    private static var stepType: HKQuantityType { HKQuantityType(.stepCount) }

    /// Fragt einmal nach Lesezugriff - danach tut der Aufruf nichts mehr.
    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await HKHealthStore().requestAuthorization(toShare: [], read: [stepType])
    }

    /// `nil`, solange Health nicht gefragt wurde - sonst stuende „0“ da, bis die
    /// App einmal offen war - und wenn Health gerade nicht lesbar ist (die Uhr
    /// ist gesperrt, etwa nicht am Handgelenk).
    static func today(now: Date = Date(), calendar: Calendar = .current) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        guard let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [stepType]),
              status == .unnecessary
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now)
        let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: stepType, predicate: predicate),
                                                options: .cumulativeSum)
        do {
            let sum = try await query.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            return Int(sum.rounded())
        } catch let error as HKError where error.code == .errorNoData {
            // Kurz nach Mitternacht: noch kein Schritt.
            return 0
        } catch {
            return nil
        }
    }
}
