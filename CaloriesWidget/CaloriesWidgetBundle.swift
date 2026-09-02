import SwiftUI
import WidgetKit

/// Der Einstieg der Erweiterung.
///
/// Muss in CaloriesWidget/ liegen und nicht in Shared/ oder Cockpit/: ein
/// zweites `@main` im App-Modul bricht den Build mit einem Fehler, der auf
/// CockpitApp.swift zeigt - also auf die Datei, an der niemand etwas geaendert
/// hat.
@main
struct CaloriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
    }
}
