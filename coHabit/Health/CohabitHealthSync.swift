import Foundation
import HealthKit

/// Schritte, Lauf-/Gehdistanz und Trainings aus Apple Health in die
/// Co-Habits, die das wollen (Vertrag §3.9, F14).
///
/// Je Co-Habit mit Health-Metrik **und** Einwilligung (`healthConsent`) liest
/// die App die Tageswerte der Nachtragsfrist - mindestens heute und gestern -
/// in der Zone des Co-Habits und schickt je Tag **eine Zahl**
/// (`PUT /cohabits/{id}/health/{date}`). Der Dienst sieht nie Rohdaten.
///
/// Welche Co-Habits das sind, merkt sich die App aus jedem geladenen Detail:
/// „Heute" kennt die Metrik nicht, und alle Details bei jedem Start zu holen
/// kostete je Co-Habit eine Anfrage.
///
/// `KCAL` gehoert nicht dazu: die kcal holt der Dienst selbst aus Healthy
/// (`source: HEALTHY`) - dafuer liest die App nichts aus Apple Health und
/// fragt auch nicht nach einer Erlaubnis.
@MainActor
final class CohabitHealthSync {

    static let shared = CohabitHealthSync()

    struct Subscription: Codable, Hashable {
        let cohabitId: String
        let metric: String
        let zone: String
        let backfillHours: Int
    }

    private let store = HKHealthStore()
    private let subscriptionsKey = "health.subscriptions"
    private let sentKey = "health.sent"
    private let lastSyncKey = "health.lastSync"
    private var isSyncing = false

    private init() {}

    var isAvailable: Bool {
        #if DEBUG
        // Der Health-Dialog laesst sich im Simulator nicht wegklicken und
        // verdeckt jeden Screenshot - wie in Healthy.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_HEALTH"] == "1" { return false }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning), HKObjectType.workoutType()]
    }

    /// Fragt nach der Leseerlaubnis. iOS zeigt den Dialog je Datentyp nur
    /// einmal; danach entscheidet die Health-App.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Ob der Dialog schon da war - fuer „verbunden" im Profil. Ob gelesen
    /// werden darf, verraet HealthKit bewusst nicht.
    func hasAsked() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return status == .unnecessary
    }

    // MARK: - Welche Co-Habits

    /// Was die App aus Apple Health liest - alles andere (`KCAL`) kommt
    /// nicht vom Geraet.
    nonisolated static let deviceMetrics: Set<String> = ["STEPS", "RUNNING_DISTANCE", "WORKOUTS", "WORKOUT_MINUTES"]

    nonisolated static func readsFromDevice(_ metric: String) -> Bool {
        deviceMetrics.contains(metric)
    }

    var subscriptions: [Subscription] {
        guard let data = UserDefaults.standard.data(forKey: subscriptionsKey) else { return [] }
        let list = (try? JSONDecoder().decode([Subscription].self, from: data)) ?? []
        return list.filter { Self.readsFromDevice($0.metric) }
    }

    /// Aus jedem geladenen Detail: Metrik und Einwilligung nachziehen. Ein
    /// Co-Habit mit kcal aus Healthy wird nie abonniert.
    func update(from detail: CohabitDetail) {
        var list = subscriptions.filter { $0.cohabitId != detail.id }
        if let health = detail.config.health, Self.readsFromDevice(health.metric),
           detail.mySettings.healthConsent, !detail.summary.archived {
            list.append(Subscription(cohabitId: detail.id, metric: health.metric,
                                     zone: detail.config.timezone, backfillHours: detail.config.backfillHours))
        }
        save(list)
    }

    func remove(_ cohabitId: String) {
        save(subscriptions.filter { $0.cohabitId != cohabitId })
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: subscriptionsKey)
        UserDefaults.standard.removeObject(forKey: sentKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    private func save(_ list: [Subscription]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: subscriptionsKey)
    }

    // MARK: - Abgleich

    /// Beim Start und bei jedem Vordergrund - hoechstens alle zehn Minuten.
    func syncIfDue() async {
        if let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
           Date().timeIntervalSince(last) < 600 { return }
        await sync()
    }

    /// Liest und schickt, was sich seit dem letzten Mal geaendert hat.
    func sync(only cohabitId: String? = nil) async {
        guard isAvailable, !isSyncing, Session.shared.isSignedIn else { return }
        isSyncing = true
        defer { isSyncing = false }
        var sent = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        let api = Session.shared.api()
        var changed = false
        for subscription in subscriptions where cohabitId == nil || subscription.cohabitId == cohabitId {
            let zone = TimeZone(identifier: subscription.zone) ?? CheckInTarget.defaultZone
            for day in Self.days(backfillHours: subscription.backfillHours, zone: zone) {
                let key = "\(subscription.cohabitId)|\(day.iso)"
                // Kein Wert an einem Tag, fuer den schon einer ging (in Health
                // geloescht): 0 schicken - das loescht den Eintrag beim Dienst.
                // Nie gesendete leere Tage bleiben leer.
                let measured = await value(subscription.metric, on: day, zone: zone) ?? 0
                if measured <= 0 && (sent[key] ?? 0) <= 0 { continue }
                let value = max(0, measured)
                if let previous = sent[key], abs(previous - value) < 0.0001 { continue }
                do {
                    let _: CohabitDetail = try await api.send(
                        "PUT", "/cohabits/\(subscription.cohabitId)/health/\(day.iso)",
                        body: HealthValue(value: value))
                    sent[key] = value > 0 ? value : nil
                    changed = true
                } catch CohabitError.offline {
                    UserDefaults.standard.set(sent, forKey: sentKey)
                    return
                } catch CohabitError.server(let status, _) where [400, 403, 404, 410].contains(status) {
                    // Einwilligung woanders widerrufen, Co-Habit weg oder Tag
                    // ausserhalb der Frist - nicht bei jedem Start erneut.
                    if status != 400 { remove(subscription.cohabitId) }
                    break
                } catch {
                    break
                }
            }
        }
        UserDefaults.standard.set(Self.prune(sent), forKey: sentKey)
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
        if changed { DataBus.shared.changed() }
    }

    struct HealthValue: Encodable {
        let value: Double
    }

    /// Heute und gestern immer, weiter zurueck so weit die Nachtragsfrist reicht.
    nonisolated static func days(backfillHours: Int, zone: TimeZone, now: Date = Date()) -> [CalendarDate] {
        let today = CalendarDate(date: now, in: zone)
        let earliest = CalendarDate(date: now.addingTimeInterval(-Double(backfillHours) * 3600), in: zone)
        var days: [CalendarDate] = []
        var day = today
        while days.count < 15 {
            days.append(day)
            let previous = day.adding(days: -1)
            if previous < earliest && days.count >= 2 { break }
            day = previous
        }
        return days
    }

    /// Nur die letzten drei Wochen merken - mehr liest ohnehin niemand nach.
    nonisolated private static func prune(_ sent: [String: Double]) -> [String: Double] {
        let cutoff = CalendarDate.today().adding(days: -21).iso
        return sent.filter { key, _ in
            guard let date = key.split(separator: "|").last else { return false }
            return String(date) >= cutoff
        }
    }

    // MARK: - HealthKit

    private func value(_ metric: String, on day: CalendarDate, zone: TimeZone) async -> Double? {
        let start = day.startOfDay(in: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        // Wie die Health-App: eine Messung ueber Mitternacht zaehlt zum Tag,
        // an dem sie begann.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        switch metric {
        case "STEPS":
            return await sum(.stepCount, unit: .count(), predicate: predicate)
        case "RUNNING_DISTANCE":
            return await sum(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), predicate: predicate)
                .map { ($0 * 100).rounded() / 100 }
        case "WORKOUTS":
            return await workouts(predicate: predicate).map { Double($0.count) }
        case "WORKOUT_MINUTES":
            return await workouts(predicate: predicate).map { list in
                (list.reduce(0) { $0 + $1.duration } / 60).rounded()
            }
        case "KCAL":
            // Kommt aus Healthy, der Dienst holt es selbst - hier nichts lesen.
            return nil
        default:
            return nil
        }
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier),
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func workouts(predicate: NSPredicate) async -> [WorkoutSpan]? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let spans = (samples as? [HKWorkout] ?? []).map { WorkoutSpan(duration: $0.duration) }
                continuation.resume(returning: spans)
            }
            store.execute(query)
        }
    }

    /// Nur die Dauer - `HKWorkout` ist nicht versendbar.
    private struct WorkoutSpan: Sendable {
        let duration: TimeInterval
    }
}

/// Ob die angemeldete Person einen Healthy-Zugang hat (Quelle `FOOD` in
/// `MeView.sources`) - nur dann kann sie den kcal aus Healthy zustimmen; der
/// Dienst lehnt sonst mit 400 ab.
enum HealthyAccess {
    @MainActor static var isAvailable: Bool {
        Session.shared.me?.sources.contains("FOOD") ?? false
    }
}
