import Foundation

/// Haelt die klassische Liste und schickt Haken, Rueckfaelle und Aenderungen -
/// wie frueher der `HabitsStore` der Fokus-App, nur gegen coHabit.
///
/// Der Dienst antwortet auf jede Aenderung mit dem neuen Stand des Habits; der
/// ersetzt die Zeile, statt dass die Liste komplett neu laedt. Ohne Netz gehen
/// Haken und Ruecknahmen in den Postausgang von coHabit, alles andere endet in
/// einer Fehlerzeile.
@MainActor
@Observable
final class ClassicStore {

    /// Was die uebrige App erfahren muss: danach laden ihre Bildschirme neu und
    /// die Kacheln holen sich ihren Stand - wie nach jeder Aktion in coHabit.
    enum Event: Equatable {
        /// Die Liste ist frisch geladen.
        case loaded
        /// Aufbauen, heute abgehakt: die Kachel zeigt sofort „erledigt".
        case markedToday(String)
        /// Rueckfall, Ruecknahme, Nachtrag, angelegt, geaendert.
        case updated(String)
        /// Geloescht oder verlassen.
        case removed(String)
        /// Heute abgehakt, aber ohne Netz im Postausgang.
        case queuedToday(String)
    }

    private(set) var habits: [ClassicHabit] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Fuer welche Habits gerade das Beweisfoto-Blatt vorbereitet wird.
    private(set) var preparingPhoto: Set<String> = []
    /// Der Stand von `DataBus`, den die eigene letzte Aenderung angestossen
    /// hat - darauf muss diese Liste nicht neu laden, die Antwort des Dienstes
    /// steht schon drin.
    private(set) var ownRevision: Int?

    private let makeAPI: @MainActor () -> CohabitAPI
    private let outbox: CohabitOutbox
    private let publish: @MainActor (Event) -> Void

    init(makeAPI: @escaping @MainActor () -> CohabitAPI = { Session.shared.api() },
         outbox: CohabitOutbox = .shared,
         publish: @escaping @MainActor (Event) -> Void = ClassicStore.publishToApp) {
        self.makeAPI = makeAPI
        self.outbox = outbox
        self.publish = publish
    }

    private var api: ClassicAPI { ClassicAPI(api: makeAPI()) }

    func load() async {
        isLoading = habits.isEmpty
        defer { isLoading = false }
        do {
            habits = try await api.list().classicOrder
            errorMessage = nil
            publish(.loaded)
        } catch {
            await report(error)
        }
    }

    /// Was der Knopf am Habit tut - je nach Art etwas anderes (`ClassicHabit.action`).
    ///
    /// Aufbauen: Haken setzen oder zuruecknehmen; mit Foto-Pflicht oeffnet der
    /// Haken das Beweisfoto-Blatt. Lassen: Rueckfall eintragen oder
    /// zuruecknehmen - „erledigt" heisst dort: kein Rueckfall. Ziel und
    /// Challenge: eintragen wie in der neuen Liste.
    func toggleToday(_ habit: ClassicHabit) async {
        switch habit.action {
        case .mark:
            await setMarked(habit, day: habit.today, marked: habit.kind == .quit ? habit.doneToday : !habit.doneToday)
        case .proofPhoto:
            await startPhotoCheckIn(habit)
        case .checkIn:
            startCheckIn(habit)
        case .none:
            return
        }
    }

    /// Ziel und Challenge: derselbe Weg wie der Eintragen-Knopf der neuen
    /// Liste und der Detailseite - ob Wert, +1 oder Beweisfoto, entscheidet
    /// `CheckInController` aus der Zusammenfassung, nicht die Liste.
    func startCheckIn(_ habit: ClassicHabit) {
        guard let summary = habit.summary, summary.canCheckIn else { return }
        CheckInController.shared.start(CheckInTarget(summary: summary, meId: Session.shared.meId))
    }

    /// Einen Tag abhaken oder den Haken nehmen - bei „Lassen" heisst der
    /// Eintrag Rueckfall. Nur fuer Habits, die man selbst abhakt.
    func setMarked(_ habit: ClassicHabit, day: CalendarDate, marked: Bool) async {
        guard habit.kind.takesMarks else { return }
        let api = self.api
        let isToday = day == habit.today
        if marked {
            let request = ClassicMarkRequest(date: day)
            do {
                replace(try await api.mark(id: habit.id, request))
                announce(habit.kind == .build && isToday ? .markedToday(habit.id) : .updated(habit.id))
            } catch CohabitError.offline {
                // Dieselbe Kennung geht spaeter raus - kommt der erste Versuch
                // doch noch an, entsteht trotzdem nur ein Eintrag.
                await outbox.enqueueClassicMark(habitId: habit.id, request: request)
                errorMessage = nil
                if habit.kind == .build && isToday { publish(.queuedToday(habit.id)) }
            } catch {
                await report(error)
            }
        } else {
            do {
                replace(try await api.unmark(id: habit.id, date: day))
                announce(.updated(habit.id))
            } catch CohabitError.offline {
                await outbox.enqueueClassicUnmark(habitId: habit.id, date: day)
                errorMessage = nil
            } catch {
                await report(error)
            }
        }
    }

    /// Foto-Pflicht: dasselbe Beweisfoto-Blatt wie der Kamera-Knopf auf dem
    /// Dashboard, mit denselben Angaben - die stehen in der Zusammenfassung
    /// des Co-Habits, nicht in der klassischen Antwort (Farbe, wer das Foto
    /// sieht). Ohne Netz und ohne letzten Stand geht es mit dem, was die Liste
    /// weiss; der Eintrag wartet dann samt Foto im Postausgang.
    func startPhotoCheckIn(_ habit: ClassicHabit) async {
        guard !preparingPhoto.contains(habit.id) else { return }
        preparingPhoto.insert(habit.id)
        defer { preparingPhoto.remove(habit.id) }
        let target: CheckInTarget
        do {
            let detail: CohabitDetail = try await makeAPI().get("/cohabits/\(habit.id)")
            CohabitGroup.remember(zone: detail.config.timezone, for: detail.id)
            target = CheckInTarget(summary: detail.summary, meId: Session.shared.meId)
        } catch {
            if await Session.shared.handle(error) { return }
            target = CheckInTarget(classic: habit)
        }
        CheckInController.shared.start(target)
    }

    /// - Returns: die Meldung des Dienstes, wenn er ablehnt - sonst `nil`.
    func create(_ draft: ClassicHabitDraft) async -> String? {
        do {
            let created = try await api.create(draft)
            habits = (habits + [created]).classicOrder
            errorMessage = nil
            announce(.updated(created.id))
            return nil
        } catch {
            if await Session.shared.handle(error) { return nil }
            return error.localizedDescription
        }
    }

    /// Name, Ziele und Rhythmus eines Habits aendern; die Art bleibt.
    /// - Returns: die Meldung des Dienstes, wenn er ablehnt - sonst `nil`.
    func update(_ habit: ClassicHabit, _ draft: ClassicHabitDraft) async -> String? {
        do {
            replace(try await api.update(id: habit.id, draft))
            announce(.updated(habit.id))
            return nil
        } catch {
            if await Session.shared.handle(error) { return nil }
            return error.localizedDescription
        }
    }

    /// Die Kategorien aus dem Wald fuer den Editor (Fokus-Zeit).
    func focusCategories() async -> [FocusCategory] {
        await FocusCategoryChoices.load(api: makeAPI())
    }

    /// Allein: loeschen. Geteilt: verlassen - das entscheidet der Dienst.
    func delete(_ habit: ClassicHabit) async {
        do {
            try await api.delete(id: habit.id)
            habits.removeAll { $0.id == habit.id }
            errorMessage = nil
            announce(.removed(habit.id))
        } catch {
            await report(error)
        }
    }

    private func replace(_ updated: ClassicHabit) {
        if let index = habits.firstIndex(where: { $0.id == updated.id }) {
            habits[index] = updated
        }
        errorMessage = nil
    }

    /// Meldet eine eigene Aenderung und merkt sich, welchen Stand von
    /// `DataBus` sie ausgeloest hat.
    private func announce(_ event: Event) {
        publish(event)
        ownRevision = DataBus.shared.revision
    }

    private func report(_ error: Error) async {
        // 401: der Token gilt nicht mehr - die Sitzung raeumt auf, die App
        // steht wieder am Start.
        if await Session.shared.handle(error) { return }
        errorMessage = error.localizedDescription
    }

    /// Auf demselben Weg wie die uebrigen Aktionen in coHabit
    /// (`CheckInController`, `CohabitDetailStore`): `DataBus` fuer die
    /// Bildschirme, `WidgetSync` fuer die Kacheln.
    static func publishToApp(_ event: Event) {
        switch event {
        case .loaded:
            WidgetSync.refreshSoon()
        case .markedToday(let id):
            DataBus.shared.changed()
            WidgetSync.markDone(id)
        case .updated:
            DataBus.shared.changed()
            Task { await WidgetSync.refresh() }
        case .removed(let id):
            CohabitHealthSync.shared.remove(id)
            DataBus.shared.changed()
            Task { await WidgetSync.refresh() }
        case .queuedToday(let id):
            WidgetSync.markDone(id)
        }
    }
}

extension CheckInTarget {
    /// Das Beweisfoto-Blatt fuer ein Habit der klassischen Liste, wenn die
    /// Zusammenfassung des Co-Habits nicht zu haben ist: Farbe aus dem letzten
    /// Stand der Kachel (sonst die des Typs), ohne die Namen der anderen.
    init(classic habit: ClassicHabit) {
        let type: CohabitType = habit.kind == .quit ? .abstinence : .streak
        id = habit.id
        name = habit.name
        color = CohabitGroup.loadWidgetData()?.cohabits.first { $0.ref.id == habit.id }?.ref.color ?? type.palette
        self.type = type
        photoRequired = habit.photoRequired
        valueUnit = nil
        label = habit.photoRequired ? "Beweisfoto & abhaken" : "Abhaken"
        otherMembers = []
        backfillFrom = nil
        zone = CohabitGroup.zone(for: habit.id) ?? Self.defaultZone
    }
}
