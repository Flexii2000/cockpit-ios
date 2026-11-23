import SwiftUI
import WidgetKit

struct RingsEntry: TimelineEntry {
    let date: Date
    let rings: HealthRings
}

/// Holt alle drei Werte selbst, wie die kcal-Komplikation: kcal beim
/// Kalorienzaehler, Strain und Schrittziel beim Weight Tracker, die Schritte
/// aus Health auf der Uhr. Was nicht antwortet, kommt aus dem Stand von heute
/// (`RingsSnapshot`), sonst steht „–“ da.
struct RingsProvider: TimelineProvider {

    func placeholder(in context: Context) -> RingsEntry {
        RingsEntry(date: Date(), rings: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (RingsEntry) -> Void) {
        // Die Auswahl beim Bearbeiten des Zifferblatts zeigt erfundene Werte -
        // dort waere „–“ nur verwirrend.
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<RingsEntry>) -> Void) {
        Task {
            let now = Date()
            completion(Timeline(entries: [await entry(now: now)],
                                policy: .after(HealthRings.nextRefresh(after: now))))
        }
    }

    private func entry(now: Date = Date()) async -> RingsEntry {
        async let kcal = KcalToday.load(now: now)
        async let fetch = Self.fetch(now: now)
        let (day, fresh) = await (kcal, fetch)
        let snapshot = RingsSnapshot.merged(fresh, stored: ComplicationStore.rings(),
                                            today: CalendarDate(date: now).iso)
        ComplicationStore.save(rings: snapshot)
        return RingsEntry(date: now, rings: HealthRings(
            kcalConsumed: day.consumed, kcalTarget: day.target, steps: snapshot.steps,
            stepsGoal: snapshot.stepsGoal ?? HealthRings.defaultStepsGoal,
            strain: snapshot.strain, targetStrain: snapshot.targetStrain))
    }

    private static func fetch(now: Date) async -> RingsFetch {
        async let steps = WatchStepCount.today(now: now)
        guard let cookie = ComplicationStore.weightCookie() else {
            return RingsFetch(steps: await steps)
        }
        let client = APIClient(backend: .weight, cookie: cookie, timeout: 10)
        async let strain = strainToday(client)
        async let goal = stepsGoal(client)
        return await RingsFetch(steps: steps, stepsGoal: goal, strain: strain)
    }

    private static func strainToday(_ client: APIClient) async -> WatchStrain? {
        try? await client.get("/api/strain/today")
    }

    private static func stepsGoal(_ client: APIClient) async -> Int? {
        let goal: StepsGoalResponse? = try? await client.get("/api/steps/goal")
        return goal.flatMap { $0.stepsPerDay > 0 ? $0.stepsPerDay : nil }
    }
}

/// `GET /api/steps/goal` - die App liest dasselbe als `StepsGoal`.
private struct StepsGoalResponse: Decodable {
    let stepsPerDay: Int
}

/// kcal, Schritte und Strain als drei Ringe (Felix, 20.11.) - fuer die Mitte des
/// Modular-Zifferblatts.
struct RingsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.watchRings, provider: RingsProvider()) { entry in
            HealthRingsView(rings: entry.rings)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ringe")
        .description("kcal, Schritte, Strain")
        .supportedFamilies([.accessoryRectangular])
    }
}
