import SwiftUI
import WidgetKit

struct StepsEntry: TimelineEntry {
    let date: Date
    let reading: StepsReading
}

/// Schritte gegen das Tagesziel - kein Netz, nur der Spiegel der App und der
/// Schrittzaehler des iPhones (`StepsNow`).
struct StepsProvider: TimelineProvider {

    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: Date(), reading: StepsReading(steps: nil, goal: StepsMirror.defaultGoal))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StepsEntry) -> Void) {
        Task { completion(StepsEntry(date: Date(), reading: await StepsNow.read())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StepsEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = StepsEntry(date: now, reading: await StepsNow.read(now: now))
            completion(Timeline(entries: [entry], policy: .after(StepsNow.nextRefresh(after: now))))
        }
    }
}

/// Der Ring mit den Schritten von heute (Sperrbildschirm, 14.10.).
struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.steps, provider: StepsProvider()) { entry in
            StepsCircleView(reading: entry.reading)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "healthy://dashboard"))
        }
        .configurationDisplayName("Schritte")
        .description("Schritte von heute gegen dein Ziel.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let calories: WidgetState
    let steps: StepsReading
}

/// kcal und Schritte - holt den Tag beim Kalorienzaehler wie die Kalorien-Kachel.
struct TodayProvider: TimelineProvider {

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), calories: .unreachable(nil),
                   steps: StepsReading(steps: nil, goal: StepsMirror.defaultGoal))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        Task { completion(await entry(now: Date())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task {
            let now = Date()
            // Der fruehere der beiden Termine: Schritte alle 20 Minuten, kcal
            // spaetestens nach einer halben Stunde, beide um Mitternacht.
            let next = min(StepsNow.nextRefresh(after: now), RemainingCalories.nextRefresh(after: now))
            completion(Timeline(entries: [await entry(now: now)], policy: .after(next)))
        }
    }

    private func entry(now: Date) async -> TodayEntry {
        async let calories = CaloriesSource.state()
        async let steps = StepsNow.read(now: now)
        return TodayEntry(date: now, calories: await calories, steps: await steps)
    }
}

/// Die grosse Sperrbildschirm-Kachel: zwei Ringe, kcal und Schritte (14.10.).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayProvider()) { entry in
            TodayOverviewView(calories: entry.calories, steps: entry.steps)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "healthy://dashboard"))
        }
        .configurationDisplayName("Heute")
        .description("Übrige kcal und Schritte von heute.")
        .supportedFamilies([.accessoryRectangular])
    }
}
