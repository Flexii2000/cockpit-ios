import SwiftUI
import WidgetKit

/// Der Einstieg der Fokus-Erweiterung - heute nur die Habits-Kachel.
@main
struct FokusWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
    }
}
