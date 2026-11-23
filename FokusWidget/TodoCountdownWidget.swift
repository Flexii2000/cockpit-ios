import AppIntents
import SwiftUI
import WidgetKit

// Der Countdown bis zur Faelligkeit einer Aufgabe (Felix 17.11., etwa „Klausur
// in 60 Tagen“). Welche Aufgabe, waehlt er per „Widget bearbeiten“ - so gehen
// mehrere Kacheln fuer mehrere Aufgaben, und der To-Do-Dienst bleibt, wie er ist.

// MARK: - Auswahl der Aufgabe

/// Eine Aufgabe in der Auswahl von „Widget bearbeiten“.
struct TodoCountdownEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "To-Do")
    static let defaultQuery = TodoCountdownQuery()

    let id: String
    let title: String
    /// „Uni · Sa 16.01.“ - unterscheidet gleichnamige Aufgaben.
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        detail.isEmpty ? DisplayRepresentation(title: "\(title)")
                       : DisplayRepresentation(title: "\(title)", subtitle: "\(detail)")
    }

    init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }

    init(_ todo: TodoCountdown, today: CalendarDate) {
        self.init(id: todo.id, title: todo.title,
                  detail: [todo.area, todo.dateText(today: today)].compactMap { $0 }.joined(separator: " · "))
    }
}

struct TodoCountdownQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [TodoCountdownEntity] {
        let today = CalendarDate.today()
        guard case .loaded(let todos) = await TodoCountdownSource.load() else {
            // Ohne Brett die Wahl behalten - sonst zeigte die Kachel ohne Netz
            // still eine andere Aufgabe.
            return identifiers.map { TodoCountdownEntity(id: $0, title: "To-Do", detail: "") }
        }
        return todos.filter { identifiers.contains($0.id) }.map { TodoCountdownEntity($0, today: today) }
    }

    /// Nur offene Aufgaben mit Faelligkeit - ohne Datum gibt es nichts zu zaehlen.
    func suggestedEntities() async throws -> [TodoCountdownEntity] {
        let today = CalendarDate.today()
        guard case .loaded(let todos) = await TodoCountdownSource.load() else { return [] }
        return TodoCountdown.choices(in: todos).map { TodoCountdownEntity($0, today: today) }
    }
}

struct SelectTodoCountdownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "To-Do wählen"

    @Parameter(title: "To-Do")
    var todo: TodoCountdownEntity?

    init() {}
}

// MARK: - Daten

/// Holt das Brett selbst: die Erweiterung sieht den Cookie-Speicher der App
/// nicht, der Token kommt aus der geteilten Keychain-Gruppe (ab dem ersten
/// Entsperren lesbar). Ohne Netz gilt der letzte Stand aus den eigenen
/// UserDefaults - die Dateien des Offline-Caches sind gesperrt, solange das
/// Telefon es ist, und gerade dann laedt der Sperrbildschirm.
enum TodoCountdownSource {

    enum Result: Sendable {
        case loaded([TodoCountdown])
        case noAccess
        case unreachable
    }

    /// Knapp - eine Erweiterung bekommt wenig Zeit.
    private static let timeout: TimeInterval = 12
    private static let cacheKey = "widget.todoCountdown.last"

    static func load() async -> Result {
        guard let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty else { return .noAccess }
        let api = TodoAPI(cookie: "\(Keychain.privateTokenKey)=\(token)", timeout: timeout)
        do {
            let todos = TodoCountdown.all(in: try await api.board())
            save(todos)
            return .loaded(todos)
        } catch APIError.notAuthorised {
            // Ein alter Stand waere hier irrefuehrend.
            return .noAccess
        } catch {
            return cached().map { .loaded($0) } ?? .unreachable
        }
    }

    private static func cached() -> [TodoCountdown]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([TodoCountdown].self, from: data)
    }

    private static func save(_ todos: [TodoCountdown]) {
        guard let data = try? JSONEncoder().encode(todos) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - Zeitleiste

struct TodoCountdownEntry: TimelineEntry {
    let date: Date
    let state: TodoCountdownWidgetState

    /// Fuer die Galerie - nie Felix' Aufgaben.
    static var sample: TodoCountdownEntry {
        TodoCountdownEntry(date: Date(), state: .countdown(TodoCountdown(
            id: "sample", title: "Klausur", area: nil, dueAt: CalendarDate.today().adding(days: 60), isDone: false)))
    }
}

struct TodoCountdownProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> TodoCountdownEntry { .sample }

    func snapshot(for configuration: SelectTodoCountdownIntent, in context: Context) async -> TodoCountdownEntry {
        if context.isPreview { return .sample }
        return TodoCountdownEntry(date: Date(), state: await state(for: configuration))
    }

    func timeline(for configuration: SelectTodoCountdownIntent,
                  in context: Context) async -> Timeline<TodoCountdownEntry> {
        let now = Date()
        let state = await state(for: configuration)
        // Die Zahl springt um Mitternacht, auch ohne Netz: ein Eintrag je Tageswechsel.
        let entries = ([now] + TodoCountdown.midnights(after: now, count: 7))
            .map { TodoCountdownEntry(date: $0, state: state) }
        // Stuendlich neu holen. Geaendert wird meist in der App, und die laedt
        // die Kachel dann selbst neu (TodoStore) - aber manchmal im Browser.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60)))
    }

    private func state(for configuration: SelectTodoCountdownIntent) async -> TodoCountdownWidgetState {
        switch await TodoCountdownSource.load() {
        case .noAccess:
            return .noAccess
        case .unreachable:
            return .unreachable
        case .loaded(let todos):
            guard let todo = TodoCountdown.pick(configuration.todo?.id, in: todos, today: .today()) else {
                return .empty
            }
            return .countdown(todo)
        }
    }
}

// MARK: - Kachel

/// Klein auf dem Homebildschirm, dazu rund, rechteckig und als Zeile auf dem
/// Sperrbildschirm (Felix' Wahl, 17.11.).
struct TodoCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.todoCountdown, intent: SelectTodoCountdownIntent.self,
                               provider: TodoCountdownProvider()) { entry in
            TodoCountdownFamilyView(entry: entry)
                // Ein Tipp fuehrt ins To-Do (RootView.onOpenURL).
                .widgetURL(URL(string: "cockpit://todo"))
        }
        .configurationDisplayName("Countdown")
        .description("Tage bis zur Fälligkeit eines To-Dos.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct TodoCountdownFamilyView: View {

    let entry: TodoCountdownEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let day = CalendarDate(date: entry.date)
        switch family {
        case .accessoryCircular:
            TodoCountdownCircularView(state: entry.state, day: day)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            TodoCountdownRectangularView(state: entry.state, day: day)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            TodoCountdownInlineView(state: entry.state, day: day)
                .containerBackground(.clear, for: .widget)
        default:
            TodoCountdownSmallView(state: entry.state, day: day)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}
