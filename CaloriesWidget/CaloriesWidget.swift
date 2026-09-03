import SwiftUI
import WidgetKit

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.calories, provider: CaloriesProvider()) { entry in
            FamilyBridge(state: entry.state)
                // Ohne containerBackground zeichnet iOS seit 17 gar nichts:
                // die Kachel steht in der Galerie und bleibt auf dem
                // Homebildschirm ein leeres Rechteck.
                .containerBackground(.fill.tertiary, for: .widget)
                // Ohne .widgetURL: die App macht ohnehin im Essen-Tab auf
                // (TabSelection.initial). Die Habits-Kachel hat eine - dort
                // waere der Essen-Tab der falsche Ort.
        }
        .configurationDisplayName("Kalorien")
        .description("Wie viel du heute noch übrig hast.")
        // Dazu die beiden Formen des Sperrbildschirms: der Ring neben der Uhr,
        // das Rechteck darunter.
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// Liest die Groesse aus dem Environment und reicht sie als Parameter weiter.
///
/// `CaloriesWidgetView` nimmt die Familie bewusst als Parameter, damit ein
/// Debug-Bildschirm der App dieselbe Ansicht in allen Groessen zeigen kann -
/// der Simulator kann keine Kachel auf den Homebildschirm legen.
private struct FamilyBridge: View {
    @Environment(\.widgetFamily) private var family
    let state: WidgetState

    var body: some View {
        CaloriesWidgetView(family: family, state: state)
    }
}
