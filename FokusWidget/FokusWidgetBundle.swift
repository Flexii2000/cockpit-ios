import SwiftUI
import WidgetKit

/// Der Einstieg der Fokus-Erweiterung: der Countdown der Fokus-Session und
/// deren Live-Aktivitaet, seit 17.11. der Countdown bis zur Faelligkeit einer
/// Aufgabe. Die Habits-Kachel ist mit den Habits nach coHabit umgezogen.
@main
struct FokusWidgetBundle: WidgetBundle {
    var body: some Widget {
        FocusCountdownWidget()
        TodoCountdownWidget()
        FocusLiveActivity()
    }
}
