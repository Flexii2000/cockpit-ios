import SwiftUI
import WidgetKit

/// Der Einstieg der Fokus-Erweiterung: die Habits-Kachel und die
/// Live-Aktivitaet der laufenden Fokus-Session.
@main
struct FokusWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
        FocusLiveActivity()
    }
}
