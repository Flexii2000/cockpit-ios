import SwiftUI

/// Ob das Zugang-Blatt offen ist - an einer Stelle, die jede App teilt.
///
/// Zugang ist kein Tab (iOS zeigt hoechstens fuenf), sondern ein Blatt hinter
/// dem Zahnrad. Der Zustand liegt hier und nicht im Router der jeweiligen
/// App, weil die Knoepfe, die es oeffnen, in `Core` und in den geteilten Tabs
/// stehen - und die kennen die Tabs der App nicht.
@MainActor
@Observable
final class SetupPresenter {

    static let shared = SetupPresenter()

    var isPresented = false

    private init() {
        #if DEBUG
        // COCKPIT_TAB=setup oeffnet das Blatt gleich beim Start.
        if ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "setup" {
            isPresented = true
        }
        #endif
    }
}

/// Das Zahnrad in der Leiste.
struct AccessButton: View {
    var body: some View {
        Button {
            SetupPresenter.shared.isPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Zugang")
    }
}
