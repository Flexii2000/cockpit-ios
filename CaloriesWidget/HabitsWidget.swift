import SwiftUI
import WidgetKit

/// Die Habits auf dem Homebildschirm: Flamme, Straehne, Stand von heute.
struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.habits, provider: HabitsProvider()) { entry in
            HabitsFamilyBridge(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
                // WidgetKit startet die App und reicht die Adresse an
                // `onOpenURL` durch - ohne registriertes Schema. So landet
                // ein Tipp im Habits-Tab statt im Essen-Tab.
                .widgetURL(URL(string: "cockpit://habits"))
        }
        .configurationDisplayName("Habits")
        .description("Deine Sträh­nen und was heute noch offen ist.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HabitsFamilyBridge: View {
    @Environment(\.widgetFamily) private var family
    let state: HabitsWidgetState

    var body: some View {
        HabitsWidgetView(family: family, state: state)
    }
}
