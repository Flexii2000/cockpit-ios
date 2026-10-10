import CryptoKit
import Foundation
import HealthKit
import UIKit

/// Holt Werte aus Apple Health und traegt sie im Weight Tracker ein: Naechte,
/// Energie, Schritte, Gewicht.
///
/// Zwei Wege, die sich ergaenzen:
///
/// * **`HKObserverQuery` mit Hintergrundzustellung** - iOS weckt die App, wenn
///   ein neuer Gewichtswert oder Schlaf geschrieben wird, auch wenn sie
///   beendet ist. Wann genau, entscheidet das System.
/// * **Abgleich im Vordergrund** - deckt alles ab, was das System nicht
///   zugestellt hat: beim Wechsel in den Vordergrund, beim Oeffnen des
///   Dashboards und beim Ziehen. Hoechstens alle zehn Minuten, es sei denn,
///   jemand zieht.
///
/// Geschrieben wird nur in eine Richtung: Health → Weight Tracker. Der
/// Rueckweg braeuchte einen Filter auf die eigene Quelle, sonst weckt der
/// eigene Schreibvorgang die App und der Wert liefe im Kreis.
///
/// Gerechnet wird hier nur, was der Vertrag den Apps zuweist (Tage und Naechte
/// bilden, `HealthEnergy`/`HealthNights`); Verbrauch, Defizit und Recovery
/// rechnet der Dienst.
@MainActor
@Observable
final class HealthSync {

    static let shared = HealthSync()

    /// Zaehlt Laeufe, die etwas hochgeladen haben. Dashboard und Gewicht-Tab
    /// laden darauf neu - sonst stuende dort bis zum naechsten Oeffnen der
    /// Stand von vor dem Abgleich.
    private(set) var uploads = 0

    private let store: HKHealthStore
    private let reader: HealthReader
    private let api = WeightAPI()
    private let energyApi = EnergyAPI()
    private let recoveryApi = RecoveryAPI()
    private let anchorKey = "health.bodyMass.anchor"
    @ObservationIgnored private var observers: [HKObserverQuery] = []
    @ObservationIgnored private var running: Task<Bool, Never>?
    @ObservationIgnored private var backfill: Task<Void, Never>?
    @ObservationIgnored private var lastSuccess: Date?

    private let bodyMass = HKQuantityType(.bodyMass)
    private let stepCount = HKQuantityType(.stepCount)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let basalEnergy = HKQuantityType(.basalEnergyBurned)
    private let sleep = HKCategoryType(.sleepAnalysis)
    private let hrvSdnn = HKQuantityType(.heartRateVariabilitySDNN)
    private let heartRate = HKQuantityType(.heartRate)
    private let respiratoryRate = HKQuantityType(.respiratoryRate)

    /// RMSSD kennt Health erst ab iOS 27. Beide Methoden gehen getrennt zum
    /// Dienst; welche zaehlt, entscheidet er (Vertrag §3.2) - so kalibriert
    /// der Umstieg nicht neu.
    private var hrvRmssd: HKQuantityType? {
        if #available(iOS 27, *) {
            return HKQuantityType(.heartRateVariabilityRMSSD)
        }
        return nil
    }

    /// Hoechstens ein Abgleich in dieser Zeit, ausser jemand zieht.
    static let minimumInterval: TimeInterval = 10 * 60

    /// Wie weit jeder Abgleich zuruecklieset.
    ///
    /// Nicht nur heute: fuer Schritte und Energie gibt es bewusst **keine**
    /// Hintergrundzustellung (siehe `syncSteps`), ohne dieses Fenster fehlte
    /// also jeder Tag, an dem die App nicht offen war. Erst nach mehr als
    /// dreissig solchen Tagen entsteht eine echte Luecke.
    private static let stepWindowDays = 30
    /// Beim ersten Mal die ganze Historie - danach reicht das Fenster.
    private static let stepBackfillDays = 3650
    private let stepBackfillKey = "health.steps.backfilled"

    /// Energie: das Fenster wie bei Schritten; die Historie einmalig in
    /// Bloecken zu einem Jahr (Vertrag §1.1).
    static let energyWindowDays = 30
    static let energyBackfillDays = 3650
    static let energyBlockDays = 365
    private let energyCursorKey = "health.energy.backfillCursor"

    /// Naechte: die letzten 14 bei jedem Abgleich, einmalig 425 in Bloecken
    /// zu 60 (Vertrag §2.1). 425 = ein Jahr, der laengste Logbook-Zeitraum,
    /// plus die 60 Naechte, gegen die der Dienst die aeltesten davon rechnet -
    /// sonst haetten sie keinen Score. 60 Naechte sind gut 20 kB - weit unter
    /// den 200 je Anfrage.
    static let nightWindowDays = 14
    static let nightBackfillDays = 425
    static let nightBlockDays = 60
    private let nightsCursorKey = "health.nights.backfillCursor"
    /// Der Inhalt des zuletzt geschickten Naechte-Fensters. Ein Weckruf, der
    /// nichts Neues bringt (die Uhr schreibt Schlaf in Raten), schickt nichts.
    private let nightsHashKey = "health.nights.windowHash"

    /// Huelle um HealthKits Fertig-Meldung. Sie ist nicht als `Sendable`
    /// deklariert, darf aber laut Vertrag von jedem Thread genau einmal
    /// gerufen werden - genau das passiert hier.
    private struct CompletionBox: @unchecked Sendable {
        let call: HKObserverQueryCompletionHandler
    }

    private init() {
        store = HKHealthStore()
        reader = HealthReader(store: store)
    }

    var isAvailable: Bool {
        #if DEBUG
        // Der Health-Dialog laesst sich im Simulator nicht wegklicken
        // (`simctl privacy` kennt keinen Health-Dienst) und verdeckt damit
        // jeden Screenshot. COCKPIT_NO_HEALTH=1 schaltet die Anbindung fuer
        // solche Laeufe ab.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_HEALTH"] == "1" {
            return false
        }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Erlaubnis

    /// Alles, was Healthy aus Health liest. Bewusst nicht: Hauttemperatur,
    /// Sauerstoff und Apples Tages-Ruhepuls - sie gehen in die Recovery nicht
    /// ein (docs/ENTSCHEIDUNGEN.md, 09.10.).
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [bodyMass, stepCount, activeEnergy, basalEnergy, sleep,
                                        hrvSdnn, heartRate, respiratoryRate]
        if let hrvRmssd { types.insert(hrvRmssd) }
        return types
    }

    /// Fragt nach Leseerlaubnis. Ein „nein" ist kein Fehler - dann bleibt es
    /// beim Eintragen von Hand.
    @discardableResult
    func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Erlaubnis im Zusammenhang erfragen und abgleichen.
    ///
    /// Fehlt noch eine (beim ersten Start, oder seit eine Art dazukam), fragt
    /// iOS jetzt - und danach wird sofort alles geholt, ohne auf die zehn
    /// Minuten zu warten: sonst saehe man nach dem Erlauben eine leere Karte.
    func connect() async {
        guard isAvailable else { return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        if status == .shouldRequest {
            await requestPermission()
            await syncAll(force: true)
        } else {
            await syncIfDue()
        }
    }

    // MARK: - Abgleich

    /// Ein Abgleich, wenn der letzte erfolgreiche mehr als zehn Minuten her
    /// ist. Laeuft gerade einer, wird er abgewartet statt ein zweiter
    /// gestartet.
    func syncIfDue() async {
        guard isAvailable else { return }
        if let running {
            _ = await running.value
            return
        }
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < Self.minimumInterval { return }
        await syncAll(force: false)
    }

    /// Alles in einem Lauf: Naechte → Energie → Schritte → Gewicht.
    ///
    /// Naechte zuerst: sie sind morgens das Neue, und die Recovery im
    /// Dashboard wartet darauf. Danach, ohne darauf zu warten, die einmalige
    /// Rueckholung der Historie.
    ///
    /// - Parameter force: auch ein unveraendertes Naechte-Fenster schicken -
    ///   wer zieht, will sicher sein, dass der Dienst den Stand hat.
    func syncAll(force: Bool) async {
        guard isAvailable else { return }
        if let running {
            _ = await running.value
            return
        }
        let task = Task { await self.runAll(force: force) }
        running = task
        let succeeded = await task.value
        running = nil
        if succeeded { lastSuccess = Date() }
        startBackfill()
    }

    private func runAll(force: Bool) async -> Bool {
        var succeeded = true
        var uploaded = false
        do {
            if try await syncNights(Self.days(endingAt: .today(), count: Self.nightWindowDays),
                                    skipUnchanged: !force) {
                uploaded = true
            }
        } catch {
            succeeded = false
        }
        do {
            if try await syncEnergyWindow() { uploaded = true }
        } catch {
            succeeded = false
        }
        if await syncSteps() { uploaded = true }
        if await syncNow() { uploaded = true }
        if uploaded { uploads += 1 }
        return succeeded
    }

    // MARK: - Naechte

    /// Bildet die Naechte dieser Aufwachtage und schickt sie.
    ///
    /// - Parameter skipUnchanged: nichts schicken, wenn das Fenster genauso
    ///   aussieht wie beim letzten Mal.
    /// - Returns: ob etwas hochging.
    private func syncNights(_ days: [CalendarDate], skipUnchanged: Bool) async throws -> Bool {
        let nights = try await readNights(days)
        guard !nights.isEmpty else { return false }
        let hash = Self.hash(nights)
        if skipUnchanged, hash == UserDefaults.standard.string(forKey: nightsHashKey) { return false }
        try await recoveryApi.sendNights(nights)
        UserDefaults.standard.set(hash, forKey: nightsHashKey)
        return true
    }

    /// Liest, was die Naechte dieser Aufwachtage brauchen, und bildet sie.
    ///
    /// **Jeder Fehler bricht ab** - der Dienst ersetzt eine Nacht als Ganzes,
    /// und eine Nacht ohne HRV, weil deren Abfrage scheiterte, ersetzte eine
    /// mit (Vertrag §2.1).
    private func readNights(_ days: [CalendarDate]) async throws -> [Night] {
        guard let first = days.min(), let last = days.max() else { return [] }
        // Zwei Tage vor dem ersten Aufwachtag: eine Nacht beginnt am Vorabend,
        // und ihre Phase kann aus Segmenten von noch frueher zusammenwachsen.
        let from = first.adding(days: -2).startOfDay()
        let to = min(Date(), last.adding(days: 1).startOfDay())
        let segments = try await reader.sleepSegments(from: from, to: to)
        let mains = HealthNights.mainSleeps(segments, days: days)
        guard !mains.isEmpty else { return [] }

        let milliseconds = HKUnit.secondUnit(with: .milli)
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let hrvTo = to.addingTimeInterval(HealthNights.hrvTail)
        let sdnn = try await reader.samples(hrvSdnn, unit: milliseconds, from: from, to: hrvTo)
        var rmssd: [HealthReading]?
        if let hrvRmssd {
            rmssd = try await reader.samples(hrvRmssd, unit: milliseconds, from: from, to: hrvTo)
        }
        let breathing = try await reader.samples(respiratoryRate, unit: perMinute, from: from, to: to)

        var nights: [Night] = []
        for main in mains {
            // Je Nacht eine Statistik-Abfrage statt aller Rohwerte: die Uhr
            // misst nachts bis zu alle fuenf Sekunden.
            let heart = try await reader.average(heartRate, unit: perMinute, from: main.start, to: main.end)
            if let night = HealthNights.night(main, inBed: segments, hrvSdnn: sdnn, hrvRmssd: rmssd,
                                              respiratory: breathing, sleepingHeartRate: heart) {
                nights.append(night)
            }
        }
        return nights
    }

    /// Der Weckruf fuer Schlaf: nur das Fenster der letzten 14 Naechte, und
    /// nur, wenn Health lesbar ist. Bei gesperrtem iPhone sind die Daten
    /// verschluesselt - dann lieber nichts als eine halbe Nacht.
    private func nightsDelivered() async {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        let days = Self.days(endingAt: .today(), count: Self.nightWindowDays)
        if (try? await syncNights(days, skipUnchanged: true)) == true { uploads += 1 }
    }

    /// Ein Fingerabdruck der Naechte, so wie sie verschickt wuerden.
    private static func hash(_ nights: [Night]) -> String {
        let encoder = APIClient.encoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(nights)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Energie

    /// Die letzten 30 Tage. Wie bei Schritten ohne Anker: Statistiken kennen
    /// kein „seit dem letzten Mal", und dass das wiederholte Lesen nichts
    /// kaputtmacht, sichert die Regel beim Dienst (heute und gestern das
    /// Maximum, aeltere Tage ersetzt).
    private func syncEnergyWindow() async throws -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        guard let from = calendar.date(byAdding: .day, value: -Self.energyWindowDays,
                                       to: calendar.startOfDay(for: now)) else { return false }
        return try await syncEnergy(from: from, to: now)
    }

    /// Ein Zeitraum Energie: aktiv und Ruhe als Tageskuebel, ohne
    /// Quellen-Praedikat - HealthKit fuehrt iPhone und Uhr selbst zusammen.
    /// Scheitert eine der beiden Abfragen, geht nichts hinaus.
    private func syncEnergy(from: Date, to: Date) async throws -> Bool {
        let kcal = HKUnit.kilocalorie()
        let active = try await reader.dailySums(activeEnergy, unit: kcal, from: from, to: to)
        let basal = try await reader.dailySums(basalEnergy, unit: kcal, from: from, to: to)
        let days = HealthEnergy.days(active: active, basal: basal)
        guard !days.isEmpty else { return false }
        try await energyApi.send(days)
        return true
    }

    // MARK: - Rueckholung

    /// Die einmalige Rueckholung: 425 Naechte, zehn Jahre Energie, in
    /// Bloecken mit Cursor. Nur im Vordergrund - im Hintergrund hat die App
    /// Sekunden, und ein abgebrochener Block wird ohnehin wiederholt.
    private func startBackfill() {
        guard backfill == nil, UIApplication.shared.applicationState == .active else { return }
        backfill = Task {
            await runBackfill()
            backfill = nil
        }
    }

    private func runBackfill() async {
        let today = CalendarDate.today()
        var uploaded = false
        // Naechte zuerst: sie fuellen die Baseline der Recovery.
        while UIApplication.shared.applicationState == .active,
              let block = HealthBackfill.next(after: cursor(nightsCursorKey),
                                              start: today.adding(days: -Self.nightWindowDays),
                                              oldest: today.adding(days: -Self.nightBackfillDays),
                                              blockDays: Self.nightBlockDays) {
            do {
                let nights = try await readNights(Self.days(in: block))
                if !nights.isEmpty {
                    try await recoveryApi.sendNights(nights)
                    uploaded = true
                }
                setCursor(block.from, nightsCursorKey)
            } catch {
                break
            }
        }
        while UIApplication.shared.applicationState == .active,
              let block = HealthBackfill.next(after: cursor(energyCursorKey),
                                              start: today.adding(days: -(Self.energyWindowDays + 1)),
                                              oldest: today.adding(days: -Self.energyBackfillDays),
                                              blockDays: Self.energyBlockDays) {
            do {
                if try await syncEnergy(from: block.from.startOfDay(),
                                        to: block.to.adding(days: 1).startOfDay()) {
                    uploaded = true
                }
                setCursor(block.from, energyCursorKey)
            } catch {
                break
            }
        }
        if uploaded { uploads += 1 }
    }

    private func cursor(_ key: String) -> CalendarDate? {
        UserDefaults.standard.string(forKey: key).flatMap(CalendarDate.init(iso:))
    }

    /// Erst nach erfolgreichem Senden - sonst fehlte der Block fuer immer.
    private func setCursor(_ day: CalendarDate, _ key: String) {
        UserDefaults.standard.set(day.iso, forKey: key)
    }

    /// `count` Tage bis einschliesslich `last`.
    nonisolated static func days(endingAt last: CalendarDate, count: Int) -> [CalendarDate] {
        (0..<count).reversed().map { last.adding(days: -$0) }
    }

    nonisolated static func days(in range: DayRange) -> [CalendarDate] {
        var result: [CalendarDate] = []
        var day = range.from
        while day <= range.to {
            result.append(day)
            day = day.adding(days: 1)
        }
        return result
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
    /// steht am naechsten Morgen fest. Dasselbe gilt fuer die Energie.
    ///
    /// - Returns: ob etwas hochging.
    @discardableResult
    func syncSteps() async -> Bool {
        guard isAvailable else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let erstesMal = !UserDefaults.standard.bool(forKey: stepBackfillKey)
        let tage = erstesMal ? Self.stepBackfillDays : Self.stepWindowDays
        guard let from = calendar.date(byAdding: .day, value: -tage,
                                       to: calendar.startOfDay(for: now)) else { return false }

        let values = HealthSteps.dailyValues(await stepBuckets(from: from, to: now))
        guard !values.isEmpty else { return false }
        // Eine Anfrage, nicht eine je Tag: der Nachtrag waeren sonst tausende.
        guard (try? await api.sendSteps(values)) != nil else { return false }
        // Merker erst nach erfolgreichem Senden, sonst faellt der Nachtrag
        // aus, wenn der Server gerade nicht erreichbar war.
        UserDefaults.standard.set(true, forKey: stepBackfillKey)
        return true
    }

    /// Tageskuebel zwischen zwei Zeitpunkten (`HealthReader.dailySums`).
    ///
    /// Es gibt hier **keinen** Anker wie bei `HKAnchoredObjectQuery` - ein
    /// „was ist seit dem letzten Mal dazugekommen" existiert fuer Statistiken
    /// nicht. Deshalb wird jedes Mal ein Fenster neu gelesen; dass das nichts
    /// kaputtmacht, sichert die max-Regel im Backend. Scheitert die Abfrage,
    /// ist das hier „nichts gemessen": die Karte zeigt dann den Stand des
    /// Dienstes.
    private func stepBuckets(from: Date, to: Date) async -> [StepBucket] {
        let sums = (try? await reader.dailySums(stepCount, unit: .count(), from: from, to: to)) ?? []
        return sums.map { StepBucket(dayStart: $0.dayStart, count: $0.value) }
    }

    // MARK: - Beobachter

    /// Muss frueh beim Start laufen: iOS stellt die Weckrufe nur zu, wenn zu
    /// dem Zeitpunkt eine Beobachtung eingetragen ist.
    ///
    /// Gewicht und Schlaf. Schlaf, weil die Uhr die Nacht erst nach dem
    /// Aufwachen schreibt - so steht die Recovery da, bevor jemand die App
    /// oeffnet.
    func startObserving() {
        guard isAvailable, observers.isEmpty else { return }
        observe(bodyMass) { sync in await sync.syncNow() }
        observe(sleep) { sync in await sync.nightsDelivered() }
    }

    private func observe(_ type: HKSampleType,
                         _ work: @escaping @Sendable @MainActor (HealthSync) async -> Void) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            // Der Rueckruf kommt nicht auf dem Hauptthread, und HealthKits
            // Fertig-Meldung ist kein `Sendable` - sie muss aber in die Task
            // hinein, weil sie erst NACH dem Abgleich gerufen werden darf:
            // wird sie zu frueh gerufen und die App stuerzt ab, gilt die
            // Zustellung als erledigt und der Wert ist verloren.
            let handler = CompletionBox(call: completion)
            Task { @MainActor in
                if let self { await work(self) }
                handler.call()
            }
        }
        observers.append(query)
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    // MARK: - Gewicht

    /// Holt alles, was seit dem letzten Mal dazugekommen ist, und traegt es ein.
    ///
    /// - Returns: ob etwas hochging.
    @discardableResult
    func syncNow() async -> Bool {
        guard isAvailable else { return false }
        let (samples, newAnchor) = await newSamples()
        guard !samples.isEmpty else {
            if let newAnchor { save(newAnchor) }
            return false
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
        return sent
    }

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
                // Sofort in einen eigenen Typ umschaufeln - so laesst sich die
                // Auswahl je Tag ohne HealthKit pruefen.
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
