import SwiftUI
import WidgetKit

/// Platzhalter fuer Schritt 0: hier wird nur die Signierung abgenommen.
///
/// Erst wenn App und Erweiterung zusammen auf dem Geraet laufen und die
/// bestehenden Token, HealthKit und Push unveraendert funktionieren, kommt
/// der Inhalt dazu. Ein Signierfehler und ein Codefehler gleichzeitig zu
/// suchen kostet mehr Zeit als dieser Zwischenschritt.
struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaloriesRemaining", provider: PlaceholderProvider()) { _ in
            Text("Cockpit")
                .font(.headline)
                // Ohne containerBackground zeichnet iOS seit 17 gar nichts:
                // die Kachel steht in der Galerie und bleibt auf dem
                // Homebildschirm ein leeres Rechteck.
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kalorien")
        .description("Wie viel du heute noch übrig hast.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    // Das @Sendable ist nicht Kosmetik: das Protokoll verlangt
    // `@escaping @Sendable`, und ohne bricht der Build unter
    // SWIFT_STRICT_CONCURRENCY=complete ab.
    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
