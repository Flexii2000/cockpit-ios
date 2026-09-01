import SwiftUI

/// Einmalige Eingabe der beiden Zugangstoken.
///
/// Bewusst als eigener Tab und nicht als versteckte Geste: die Token muessen
/// selten, aber verlaesslich erreichbar sein - etwa wenn eines auf dem Server
/// gewechselt wird und ploetzlich alle drei Tabs auf die Anmeldeseite
/// umleiten.
struct SetupView: View {

    @Environment(Access.self) private var access
    @State private var privateToken = ""
    @State private var weightToken = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("fh_private", text: $privateToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Privat-Token")
                } footer: {
                    Text("Gilt für alle Dienste unter fherrmann.com. "
                         + "Auf dem Server: /etc/nginx/conf.d/private-mode.conf")
                }

                Section {
                    SecureField("weight_app_token", text: $weightToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Gewichts-Token")
                } footer: {
                    Text("Nur für weight.fherrmann.com. "
                         + "Auf dem Server: /etc/health-viz.env")
                }

                Section {
                    Button("Speichern") {
                        Task {
                            await access.store(privateToken: privateToken,
                                               weightToken: weightToken)
                            saved = true
                        }
                    }
                    .disabled(privateToken.isEmpty || weightToken.isEmpty)

                    if access.isConfigured {
                        Button("Token löschen", role: .destructive) {
                            access.reset()
                            privateToken = ""
                            weightToken = ""
                        }
                    }
                } footer: {
                    if saved {
                        Text("Gespeichert. Die Tabs laden beim nächsten "
                             + "Wechsel mit dem neuen Zugang.")
                    } else {
                        Text("Die Token liegen im Keychain des Geräts und "
                             + "verlassen es nicht.")
                    }
                }
            }
            .navigationTitle("Zugang")
        }
    }
}
