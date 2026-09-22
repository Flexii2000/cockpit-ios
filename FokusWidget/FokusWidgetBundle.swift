import SwiftUI
import WidgetKit

/// Der Einstieg der Fokus-Erweiterung: die Habits-Kachel, der Countdown der
/// Fokus-Session und deren Live-Aktivitaet.
@main
struct FokusWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
        FocusCountdownWidget()
        FocusLiveActivity()
    }
}
