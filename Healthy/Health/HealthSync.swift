import Foundation
import HealthKit

/// Holt Gewichtswerte aus Apple Health und traegt sie im Weight Tracker ein.
///
/// Zwei Wege, die sich ergaenzen:
///
/// * **`HKObserverQuery` mit Hintergrundzustellung** - iOS weckt die App, wenn
///   ein neuer Wert geschrieben wird, auch wenn sie beendet ist. Wann genau,
///   entscheidet das System; fuer Koerpergewicht sind das eher Minuten als
///   Sekunden.
/// * **Abgleich beim Oeffnen** - deckt alles ab, was das System nicht
///   zugestellt hat.
///
/// Geschrieben wird nur in eine Richtung: Health → Cockpit. Der Rueckweg
/// braeuchte einen Filter auf die eigene Quelle, sonst weckt der eigene
/// Schreibvorgang die App und der Wert liefe im Kreis.
@MainActor
final class HealthSync {

    static let shared = HealthSync()

    private let store = HKHealthStore()
    private let api = WeightAPI()
    private let anchorKey = "health.bodyMass.anchor"
    private var observer: HKObserverQuery?

    private let bodyMass = HKQuantityType(.bodyMass)
    private let stepCount = HKQuantityType(.stepCount)

    /// Wie weit jeder Abgleich zuruecklieset.
    ///
    /// Nicht nur heute: fuer Schritte gibt es bewusst **keine**
    /// Hintergrundzustellung (siehe unten), ohne dieses Fenster fehlte also
    /// jeder Tag, an dem der Gewicht-Tab nicht geoeffnet wurde. Erst nach mehr
    /// als dreissig ungeoeffneten Tagen entsteht eine echte Luecke.
    private static let stepWindowDays = 30
    /// Beim ersten Mal die ganze Historie - danach reicht das Fenster.
    private static let stepBackfillDays = 3650
    private let stepBackfillKey = "health.steps.backfilled"

    /// Huelle um HealthKits Fertig-Meldung. Sie ist nicht als `Sendable`
    /// deklariert, darf aber laut Vertrag von jedem Thread genau einmal
    /// gerufen werden - genau das passiert hier.
    private struct CompletionBox: @unchecked Sendable {
        let call: HKObserverQueryCompletionHandler
    }

    var isAvailable: Bool {
        #if DEBUG
        // Der Health-Dialog laesst sich im Simulator nicht wegklicken
        // (`simctl privacy` kennt keinen Health-Dienst) und verdeckt damit
        // jeden Screenshot des Gewicht-Tabs. COCKPIT_NO_HEALTH=1 schaltet die
        // Anbindung fuer solche Laeufe ab.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_HEALTH"] == "1" {
            return false
        }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    /// Fragt nach Leseerlaubnis. Ein „nein" ist kein Fehler - dann bleibt es
    /// beim Eintragen von Hand.
    @discardableResult
    func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMass, stepCount])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Schritte

    /// Die Schrittzahl eines Tages, so wie die Health-App sie zeigt.
    ///
    /// `nil` heisst „Health weiss nichts ueber diesen Tag" - und ist etwas
    /// anderes als null Schritte.
    func todaySteps(_ day: CalendarDate = .today()) async -> Int? {
        guard isAvailable else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = day.startOfDay()
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let buckets = await stepBuckets(from: start, to: end)
        return HealthSteps.dailyValues(buckets).first?.steps
    }

    /// Liest ein Fenster und schickt es gebuendelt zum Weight Tracker.
    ///
    /// **Keine Hintergrundzustellung fuer Schritte**, obwohl das Entitlement
    /// da ist: iOS deckelt die Frequenz fuer diesen Typ auf stuendlich, und
    /// die App stuendlich zu wecken, um eine Zahl hochzuladen, die eine Stunde
    /// spaeter wieder falsch ist, kostet Funk und Akku fuer nichts. Die
    /// einzige Zahl, die dauerhaft zaehlt, ist die Tagesendsumme - und die
    /// steht am naechsten Morgen fest.
    func syncSteps() async {
        guard isAvailable else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let erstesMal = !UserDefaults.standard.bool(forKey: stepBackfillKey)
        let tage = erstesMal ? Self.stepBackfillDays : Self.stepWindowDays
        guard let from = calendar.date(byAdding: .day, value: -tage,
                                       to: calendar.startOfDay(for: now)) else { return }

        let values = HealthSteps.dailyValues(await stepBuckets(from: from, to: now))
        guard !values.isEmpty else { return }
        // Eine Anfrage, nicht eine je Tag: der Nachtrag waeren sonst tausende.
        guard (try? await api.sendSteps(values)) != nil else { return }
        // Merker erst nach erfolgreichem Senden, sonst faellt der Nachtrag
        // aus, wenn der Server gerade nicht erreichbar war.
        UserDefaults.standard.set(true, forKey: stepBackfillKey)
    }

    /// Tageskuebel zwischen zwei Zeitpunkten.
    ///
    /// Es gibt hier **keinen** Anker wie bei `HKAnchoredObjectQuery` - ein
    /// „was ist seit dem letzten Mal dazugekommen" existiert fuer Statistiken
    /// nicht. Deshalb wird jedes Mal ein Fenster neu gelesen; dass das nichts
    /// kaputtmacht, sichert die max-Regel im Backend.
    private func stepBuckets(from: Date, to: Date) async -> [StepBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let anchor = calendar.startOfDay(for: from)
        // `.strictStartDate`: ein Gang von 23:50 bis 00:10 zaehlt ganz zu dem
        // Tag, an dem er begann - genau so rechnet die Health-App. Ohne die
        // Option ginge dieselbe Messung in BEIDE Tage voll ein, und das ist
        // die eigentliche Doppelzaehlungsfalle.
        //
        // KEIN Quellen-Praedikat: ueber eine Statistik-Abfrage fuehrt HealthKit
        // iPhone und Uhr selbst zusammen. Das negative Praedikat aus
        // `newSamples()` gehoert zum Gewicht (eigener Rueckweg) und wuerde hier
        // im besten Fall nichts tun, im schlechteren Quellen wegfiltern.
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: to,
                                                    options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepCount,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                // Ein Tag als DateComponents und nicht als 86400 Sekunden:
                // sonst laufen die Kuebel nach jeder Zeitumstellung um eine
                // Stunde aus dem Takt.
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var buckets: [StepBucket] = []
                collection?.enumerateStatistics(from: anchor, to: to) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: .count()) {
                        buckets.append(StepBucket(dayStart: statistics.startDate, count: sum))
                    }
                }
                continuation.resume(returning: buckets)
            }
            store.execute(query)
        }
    }

    /// Muss frueh beim Start laufen: iOS stellt die Weckrufe nur zu, wenn zu
    /// dem Zeitpunkt eine Beobachtung eingetragen ist.
    func startObserving() {
        guard isAvailable, observer == nil else { return }
        let query = HKObserverQuery(sampleType: bodyMass, predicate: nil) {
            [weak self] _, completion, _ in
            // Der Rueckruf kommt nicht auf dem Hauptthread, und HealthKits
            // Fertig-Meldung ist kein `Sendable` - sie muss aber in die Task
            // hinein, weil sie erst NACH dem Abgleich gerufen werden darf:
            // wird sie zu frueh gerufen und die App stuerzt ab, gilt die
            // Zustellung als erledigt und der Wert ist verloren.
            let handler = CompletionBox(call: completion)
            Task { @MainActor in
                await self?.syncNow()
                handler.call()
            }
        }
        observer = query
        store.execute(query)
        store.enableBackgroundDelivery(for: bodyMass, frequency: .immediate) { _, _ in }
    }

    /// Holt alles, was seit dem letzten Mal dazugekommen ist, und traegt es ein.
    func syncNow() async {
        guard isAvailable else { return }
        let (samples, newAnchor) = await newSamples()
        guard !samples.isEmpty else {
            if let newAnchor { save(newAnchor) }
            return
        }
        var sent = false
        for value in HealthSamples.dailyValues(samples) {
            // `keepExisting` ist hier der Punkt: es gibt genau einen Wert pro
            // Tag, und ein von Hand eingetragener ist der verlaesslichere.
            // Ohne das haenge es davon ab, wer zuletzt geschrieben hat - und
            // das waere je nach Weckzeitpunkt von iOS mal so und mal so.
            if (try? await api.add(date: value.date, weightKg: value.value,
                                   keepExisting: true)) != nil {
                sent = true
            }
        }
        // Anker erst nach erfolgreichem Senden merken, sonst gingen Werte
        // verloren, wenn der Server gerade nicht erreichbar war.
        if sent, let newAnchor { save(newAnchor) }
    }

    // MARK: - HealthKit-Abfrage

    private func newSamples() async -> ([WeightSample], HKQueryAnchor?) {
        // Eigene Schreibvorgaenge ausschliessen: sonst weckt uns spaeter der
        // eigene Rueckweg und der Wert liefe im Kreis.
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default()))

        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: bodyMass,
                predicate: notOurs,
                anchor: loadAnchor(),
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, anchor, _ in
                // Sofort in einen Sendable-Typ umschaufeln: HKQuantitySample
                // darf den Rueckruf nicht verlassen.
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    WeightSample(takenAt: $0.startDate,
                                 kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
                continuation.resume(returning: (mapped, anchor))
            }
            store.execute(query)
        }
    }

    // MARK: - Anker

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func save(_ anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor,
                                                           requiringSecureCoding: true)
        else { return }
        UserDefaults.standard.set(data, forKey: anchorKey)
    }
}
