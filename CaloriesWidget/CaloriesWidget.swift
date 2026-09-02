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
                // Bewusst ohne .widgetURL: die App macht ohnehin im Essen-Tab
                // auf (TabSelection.initial). Ein eigenes URL-Schema braeuchte
                // CFBundleURLTypes - eine Liste von Woerterbuechern, die sich
                // nicht als INFOPLIST_KEY_ ausdruecken laesst, also eine
                // vollstaendige Info.plist von Hand. Dafuer ist der Gewinn zu
                // klein.
        }
        .configurationDisplayName("Kalorien")
        .description("Wie viel du heute noch übrig hast.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
