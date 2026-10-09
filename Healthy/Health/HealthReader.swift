import Foundation
import HealthKit

/// Ein Tageskuebel aus einer Statistik-Abfrage: Beginn des Tages und Summe.
struct DaySum: Sendable, Equatable {
    let dayStart: Date
    let value: Double
}

/// Ein Messwert aus Health (HRV, Atemfrequenz), auf das Noetige eingedampft.
struct HealthReading: Sendable, Equatable {
    let start: Date
    let value: Double
    /// Von der Apple Watch gemessen. Die Nacht bevorzugt ihre Werte - das
    /// iPhone misst HRV hoechstens mit Zusatzgeraeten, und die messen anders.
    let isWatch: Bool
}

/// Ein Schlafsegment, so wie Health es kennt: Stadium, Zeitraum, Quelle.
struct SleepSegment: Sendable, Equatable {

    enum Stage: Sendable, Equatable {
        case inBed, awake, core, deep, rem, unspecified

        /// Kern, Tief, REM und „unbestimmt" zaehlen als Schlaf; „im Bett" und
        /// „wach" nicht.
        var isAsleep: Bool {
            switch self {
            case .core, .deep, .rem, .unspecified: true
            case .inBed, .awake: false
            }
        }
    }

    let start: Date
    let end: Date
    let stage: Stage
    /// Die Bundle-ID der schreibenden App - je Geraet eine eigene, auch bei
    /// Apples eigenem Schlaf-Tracking.
    let source: String
    let isWatch: Bool
}

/// Lesezugriffe auf HealthKit - jede Abfrage als `async`, das Ergebnis sofort
/// in eigene Typen umgeschaufelt.
///
/// Eigene Typen statt `HKSample`: so laesst sich alles, was danach kommt
/// (Tage, Naechte, HRV-Zuordnung), ohne HealthKit pruefen. Und die Regeln aus
/// dem Vertrag (`weight-app/docs/HEALTHY-CONTRACT.md` §2.2) stehen in
/// `HealthNights`, nicht verteilt ueber Rueckrufe.
struct HealthReader: Sendable {

    let store: HKHealthStore

    enum Failure: Error, Equatable {
        /// Das iPhone ist gesperrt - Health-Daten sind dann verschluesselt. Wer
        /// jetzt eine Nacht ohne HRV schickte, ersetzte eine mit.
        case locked
        case failed(String)
    }

    /// `errorNoData` heisst „nichts da" und ist kein Fehler; ein gesperrtes
    /// Geraet ist einer, aber ein eigener.
    static func failure(_ error: Error) -> Failure? {
        if let health = error as? HKError {
            switch health.code {
            case .errorNoData: return nil
            case .errorDatabaseInaccessible: return .locked
            default: break
            }
        }
        return .failed(error.localizedDescription)
    }

    // MARK: - Tagessummen

    /// Tageskuebel einer Summe (Schritte, Energie) zwischen zwei Zeitpunkten.
    ///
    /// `.strictStartDate`: eine Messung zaehlt ganz zu dem Tag, an dem sie
    /// begann - so rechnet die Health-App, und nur so geht dieselbe Messung
    /// nicht in zwei Tage ein. **Kein Quellen-Praedikat**: ueber eine
    /// Statistik fuehrt HealthKit iPhone und Uhr selbst zusammen. Ein Tag als
    /// `DateComponents(day: 1)` und nicht als 86400 Sekunden - sonst laufen die
    /// Kuebel nach jeder Zeitumstellung um eine Stunde aus dem Takt.
    func dailySums(_ type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> [DaySum] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let anchor = calendar.startOfDay(for: from)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: to, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if let failure = Self.failure(error) {
                        continuation.resume(throwing: failure)
                    } else {
                        continuation.resume(returning: [])
                    }
                    return
                }
                var sums: [DaySum] = []
                collection?.enumerateStatistics(from: anchor, to: to) { statistics, _ in
                    // Kuebel ohne Messung liefern `nil` - die fallen hier heraus,
                    // eine Null waere eine Behauptung ueber einen leeren Tag.
                    if let sum = statistics.sumQuantity()?.doubleValue(for: unit) {
                        sums.append(DaySum(dayStart: statistics.startDate, value: sum))
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    // MARK: - Schlaf

    /// Alle Schlafsegmente, die das Fenster beruehren - jeder Quelle, jedes
    /// Stadiums. Welche davon eine Nacht bilden, entscheidet `HealthNights`.
    func sleepSegments(from: Date, to: Date) async throws -> [SleepSegment] {
        let samples = try await samples(of: HKCategoryType(.sleepAnalysis), from: from, to: to)
        return samples.compactMap { sample in
            guard let category = sample as? HKCategorySample,
                  let stage = Self.stage(category.value) else { return nil }
            return SleepSegment(start: category.startDate, end: category.endDate, stage: stage,
                                source: category.sourceRevision.source.bundleIdentifier,
                                isWatch: Self.isWatch(category))
        }
    }

    /// Unbekannte Werte (ein spaeteres iOS mit neuen Stadien) fallen heraus,
    /// statt geraten zu werden.
    static func stage(_ value: Int) -> SleepSegment.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed:             .inBed
        case .awake:             .awake
        case .asleepCore:        .core
        case .asleepDeep:        .deep
        case .asleepREM:         .rem
        case .asleepUnspecified: .unspecified
        default:                 nil
        }
    }

    // MARK: - Messwerte

    /// Einzelmessungen eines Typs (HRV, Atemfrequenz) im Fenster.
    func samples(_ type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> [HealthReading] {
        let samples = try await samples(of: type, from: from, to: to)
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return HealthReading(start: quantity.startDate,
                                 value: quantity.quantity.doubleValue(for: unit),
                                 isWatch: Self.isWatch(quantity))
        }
    }

    /// Das zeitgewichtete Mittel eines Typs in einem Zeitraum - bei der
    /// Herzfrequenz das, was die Health-App als Durchschnitt zeigt.
    ///
    /// Keine Rohwerte mitteln: die Uhr misst nachts mal alle paar Minuten, mal
    /// alle fuenf Sekunden, und ein schlichtes Mittel gaebe den dichten
    /// Abschnitten ein Vielfaches an Gewicht. Erst nur die Uhr; misst sie
    /// nicht, alle Quellen.
    func average(_ type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> Double? {
        let window = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let watchOnly = NSCompoundPredicate(andPredicateWithSubpredicates: [
            window,
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"]),
        ])
        if let fromWatch = try await average(type, unit: unit, predicate: watchOnly) {
            return fromWatch
        }
        return try await average(type, unit: unit, predicate: window)
    }

    private func average(_ type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .discreteAverage) { _, statistics, error in
                if let error {
                    if let failure = Self.failure(error) {
                        continuation.resume(throwing: failure)
                    } else {
                        continuation.resume(returning: nil)
                    }
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Innereien

    private func samples(of type: HKSampleType, from: Date, to: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let byStart = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [byStart]) { _, samples, error in
                if let error {
                    if let failure = Self.failure(error) {
                        continuation.resume(throwing: failure)
                    } else {
                        continuation.resume(returning: [])
                    }
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    /// Ob eine Probe von einer Apple Watch kommt. Zwei Wege, weil Apps
    /// unterschiedlich viel mitschreiben: die Produktkennung der Quelle
    /// („Watch7,1") oder das Modell des Geraets.
    private static func isWatch(_ sample: HKSample) -> Bool {
        if sample.sourceRevision.productType?.hasPrefix("Watch") == true { return true }
        return sample.device?.model == "Watch"
    }
}
