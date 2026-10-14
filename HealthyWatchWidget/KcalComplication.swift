import SwiftUI
import WidgetKit

/// Der Einstieg der Komplikationen auf der Uhr.
@main
struct HealthyWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        KcalComplication()
    }
}

struct KcalEntry: TimelineEntry {
    let date: Date
    let consumed: Double?
    let target: Double?
}

/// Holt den Tag selbst beim Kalorienzaehler - wie die Kachel auf dem iPhone
/// (Entscheidung 02.09.) - und faellt auf den Stand zurueck, den das iPhone
/// zuletzt geschickt hat (`ComplicationStore`). Ein Stand von gestern zaehlt
/// heute nicht: dann steht „–“ statt einer erfundenen Zahl.
struct KcalProvider: TimelineProvider {

    func placeholder(in context: Context) -> KcalEntry {
        KcalEntry(date: Date(), consumed: 1550, target: 2300)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (KcalEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<KcalEntry>) -> Void) {
        Task {
            let now = Date()
            completion(Timeline(entries: [await entry(now: now)],
                                policy: .after(RemainingCalories.nextRefresh(after: now))))
        }
    }

    private func entry(now: Date = Date()) async -> KcalEntry {
        let today = CalendarDate(date: now)
        if let token = ComplicationStore.token(),
           let day = try? await FoodAPI(cookie: "\(Keychain.privateTokenKey)=\(token)", timeout: 10).day(today) {
            ComplicationStore.save(snapshot: ComplicationSnapshot(date: today.iso, consumedKcal: day.consumed.kcal,
                                                                  targetKcal: day.targets.kcal, fetchedAt: now))
            return KcalEntry(date: now, consumed: day.consumed.kcal, target: day.targets.kcal)
        }
        let snapshot = ComplicationStore.snapshot()
        return KcalEntry(date: now,
                         consumed: snapshot?.date == today.iso ? snapshot?.consumedKcal : nil,
                         target: snapshot?.targetKcal)
    }
}

/// kcal gegessen gegen das Tagesziel, im Stil der Temperatur-Komplikation
/// (Felix, 14.10.: links 0, Mitte gegessen, rechts Tagesziel).
struct KcalComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.watchKcal, provider: KcalProvider()) { entry in
            KcalGaugeView(consumed: entry.consumed, target: entry.target)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kalorien")
        .description("Heute gegessen gegen dein Tagesziel.")
        .supportedFamilies([.accessoryCircular])
    }
}
