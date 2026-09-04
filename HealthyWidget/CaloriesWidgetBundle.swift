import SwiftUI
import WidgetKit

/// Der Einstieg der Erweiterung.
///
/// Muss in HealthyWidget/ liegen und nicht in Shared/ oder Healthy/: ein
/// zweites `@main` im App-Modul bricht den Build mit einem Fehler, der auf
/// HealthyApp.swift zeigt - also auf die Datei, an der niemand etwas geaendert
/// hat.
@main
struct HealthyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
    }
}
