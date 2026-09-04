import SwiftUI

/// Welche Abschnitte das Zugang-Blatt zeigt - jede App nur die, deren
/// Dienste sie benutzt.
enum SetupSection: Hashable {
    case privateToken, weightToken, grades, shoppingToken
}

/// Einmalige Eingabe der Zugangstoken.
///
/// Ein Blatt, erreichbar ueber das Zahnrad - kein Tab, seit iOS fuenf davon
/// als Maximum kennt. Jeder Abschnitt hat seinen eigenen Speichern-Knopf: die
/// Token gehoeren verschiedenen Diensten, und wer nur einen wechselt, soll
/// nicht alle neu eingeben muessen. Die Eintraege liegen in der geteilten
/// Keychain-Gruppe, einmal eingegeben gelten sie fuer alle drei Apps.
struct SetupView: View {

    let sections: Set<SetupSection>

    @Environment(Access.self) private var access
    @Environment(\.dismiss) private var dismiss

    @State private var privateToken = ""
    @State private var weightToken = ""
    @State private var privateSaved = false
    @State private var weightSaved = false

    @State private var gradesToken = ""
    @State private var gradesUser = ""
    @State private var gradesPassword = ""
    @State private var gradesSaved = false
    @State private var gradesFailure: String?

    @State private var shoppingToken = ""
    @State private var shoppingSaved = false

    var body: some View {
        NavigationStack {
            Form {
                if sections.contains(.privateToken) { privateSection }
                if sections.contains(.weightToken) { weightSection }
                if sections.contains(.grades) { gradesSection }
                if sections.contains(.shoppingToken) { shoppingSection }
                Section {
                    Text("Die Token liegen im Keychain des Geräts, geteilt zwischen "
                         + "Healthy, Vault, Fokus und Einkauf - einmal eingegeben, überall da.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    // MARK: - Privat-Token

    private var privateSection: some View {
        Section {
            SecureField("fh_private", text: $privateToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Speichern") {
                Task {
                    await access.store(privateToken: privateToken)
                    privateSaved = true
                    privateToken = ""
                }
            }
            .disabled(privateToken.isEmpty)
            if access.privateToken != nil {
                Button("Löschen", role: .destructive) {
                    access.resetPrivateToken()
                    privateSaved = false
                }
            }
        } header: {
            Text("Privat-Token" + (access.privateToken != nil ? " ✓" : ""))
        } footer: {
            Text(privateSaved ? "Gespeichert."
                 : "Gilt für Essen, Habits und das Widget (alles unter fherrmann.com). "
                   + "Auf dem Server: /etc/nginx/conf.d/private-mode.conf")
        }
    }

    // MARK: - Gewichts-Token

    private var weightSection: some View {
        Section {
            SecureField("weight_app_token", text: $weightToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Speichern") {
                Task {
                    await access.store(weightToken: weightToken)
                    weightSaved = true
                    weightToken = ""
                }
            }
            .disabled(weightToken.isEmpty)
            if access.weightToken != nil {
                Button("Löschen", role: .destructive) {
                    access.resetWeightToken()
                    weightSaved = false
                }
            }
        } header: {
            Text("Gewichts-Token" + (access.weightToken != nil ? " ✓" : ""))
        } footer: {
            Text(weightSaved ? "Gespeichert."
                 : "Nur für weight.fherrmann.com. Auf dem Server: /etc/health-viz.env")
        }
    }

    // MARK: - Einkaufsliste

    private var shoppingSection: some View {
        Section {
            SecureField("shopping_token", text: $shoppingToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("shoppingToken")
            Button("Speichern") {
                Task {
                    await access.store(shoppingToken: shoppingToken)
                    shoppingSaved = true
                    shoppingToken = ""
                }
            }
            .disabled(shoppingToken.isEmpty)
            if access.shoppingToken != nil {
                Button("Löschen", role: .destructive) {
                    access.resetShoppingToken()
                    shoppingSaved = false
                }
            }
        } header: {
            Text("Einkaufsliste" + (access.shoppingToken != nil ? " ✓" : ""))
        } footer: {
            Text(shoppingSaved ? "Gespeichert."
                 : "Ein eigener Token je Person - der Setup-Link "
                   + "fherrmann.com/shopping-list/setup?token=… enthält ihn. "
                   + "Auf dem Server: /etc/shopping.env")
        }
    }

    // MARK: - Noten

    private var gradesSection: some View {
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
            Text("Noten" + (access.isGradesConfigured ? " ✓" : ""))
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
    }
}
