import SwiftUI

/// Einmalige Eingabe der Zugangstoken.
///
/// Ein Blatt, erreichbar ueber das Zahnrad in jedem nativen Tab - kein Tab
/// mehr, seit es fuenf Dienste gibt: iOS zeigt hoechstens fuenf in der Leiste
/// und schiebt den Rest unter „Mehr". Die Token muessen selten, aber
/// verlaesslich erreichbar sein - etwa wenn eines auf dem Server gewechselt
/// wird und ploetzlich alle Tabs auf die Anmeldeseite umleiten.
struct SetupView: View {

    @Environment(Access.self) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var privateToken = ""
    @State private var weightToken = ""
    @State private var saved = false

    @State private var gradesToken = ""
    @State private var gradesUser = ""
    @State private var gradesPassword = ""
    @State private var gradesSaved = false
    @State private var gradesFailure: String?

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
                    SecureField("grades_token", text: $gradesToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Benutzer", text: $gradesUser)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Passwort", text: $gradesPassword)
                        .textContentType(.password)

                    Button("Noten-Zugang speichern") {
                        Task {
                            let ok = await access.storeGrades(token: gradesToken,
                                                              user: gradesUser,
                                                              password: gradesPassword)
                            gradesSaved = ok
                            gradesFailure = ok ? nil
                                : "Das Passwort ließ sich nicht hinter Face ID legen. "
                                  + "Ist auf dem Gerät ein Code eingerichtet?"
                            if ok { gradesPassword = "" }
                        }
                    }
                    .disabled(gradesToken.isEmpty || gradesUser.isEmpty || gradesPassword.isEmpty)

                    if access.isGradesConfigured {
                        Button("Noten-Zugang löschen", role: .destructive) {
                            access.resetGrades()
                            gradesToken = ""
                            gradesUser = ""
                            gradesPassword = ""
                            gradesSaved = false
                        }
                    }
                } header: {
                    Text("Noten")
                } footer: {
                    if let gradesFailure {
                        Text(gradesFailure).foregroundStyle(.red)
                    } else if gradesSaved {
                        Text("Gespeichert. Das Passwort liegt hinter Face ID und "
                             + "wird nur zum Anmelden gebraucht – die Sitzung "
                             + "hält danach sieben Tage.")
                    } else {
                        Text("Zwei Schranken wie im Browser: der Geräte-Token "
                             + "aus /grades/setup?token=… und die Anmeldung. "
                             + "Auf dem Server: ~/services/grades/grades.env")
                    }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
