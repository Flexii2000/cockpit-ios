import SwiftUI

/// Welche Abschnitte das Zugang-Blatt zeigt - jede App nur die, deren
/// Dienste sie benutzt.
enum SetupSection: Hashable {
    case privateToken, weightToken, grades, shoppingToken
    /// Der persoenliche Healthy-Token (seit 10.11.) - ein Feld fuer Token oder
    /// Setup-Link. Nur Healthy zeigt ihn.
    case healthToken

    /// Die Abschnitte fuer Felix' eigene Token - nur zu ihnen gehoert der
    /// Hinweis auf den geteilten Schluesselbund.
    static let owner: Set<SetupSection> = [.privateToken, .weightToken, .grades, .shoppingToken]
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
    /// Abschnitte, die zugeklappt unter „Besitzer-Token“ stehen: in Healthy auf
    /// einem iPhone ohne jeden Zugang. Dort ist der persoenliche Token der
    /// Normalfall; Felix' Token braucht nur sein eigenes Geraet.
    var collapsed: Set<SetupSection> = []

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

    @State private var healthInput = ""
    @State private var healthFailure: String?
    @State private var healthBusy = false
    @State private var showsCollapsed = false

    /// Was gerade zu sehen ist - die zugeklappten erst nach dem Aufklappen.
    private var visible: Set<SetupSection> {
        showsCollapsed ? sections.union(collapsed) : sections
    }

    var body: some View {
        NavigationStack {
            Form {
                if visible.contains(.healthToken) { healthSection }
                if !collapsed.isEmpty {
                    Section {
                        DisclosureGroup("Besitzer-Token", isExpanded: $showsCollapsed) {}
                            .accessibilityIdentifier("ownerTokens")
                    }
                }
                if visible.contains(.privateToken) { privateSection }
                if visible.contains(.weightToken) { weightSection }
                if visible.contains(.grades) { gradesSection }
                if visible.contains(.shoppingToken) { shoppingSection }
                // Gilt nur fuer Felix' Token: der persoenliche Healthy-Token
                // wird von keiner anderen App gelesen.
                if !visible.isDisjoint(with: SetupSection.owner) {
                    Section {
                        Text("Die Token liegen im Keychain des Geräts, geteilt zwischen "
                             + "Healthy, Vault, Fokus und Einkaufsliste - einmal eingegeben, überall da.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    // MARK: - Persoenlicher Healthy-Token

    /// Ein Feld fuer den Token oder den Setup-Link. Gespeichert wird erst, wenn
    /// Kalorienzaehler und Weight Tracker ihn angenommen haben - danach geht
    /// das Blatt zu, weil es sonst nichts mehr zu tun gibt.
    private var healthSection: some View {
        Section {
            SecureField("Token oder Link", text: $healthInput)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("healthToken")
            Button("Speichern") {
                Task {
                    healthBusy = true
                    healthFailure = await access.storeHealth(input: healthInput)
                    healthBusy = false
                    // Auch nach einer Absage leeren: das Feld zeigt nur Punkte,
                    // und ein zweiter Versuch haengte sich sonst an den ersten an.
                    healthInput = ""
                    if healthFailure == nil { dismiss() }
                }
            }
            .disabled(healthInput.isEmpty || healthBusy)
            if access.healthToken != nil {
                Button("Entfernen", role: .destructive) {
                    Task { await access.resetHealthToken() }
                }
            }
        } header: {
            if let header = Self.healthHeader(hasToken: access.healthToken != nil, name: access.healthName) {
                Text(header).accessibilityIdentifier("healthAccess")
            }
        } footer: {
            if let healthFailure {
                Text(healthFailure).foregroundStyle(.red)
            }
        }
    }

    /// „✓ Name“, sobald ein Token liegt - der Name, wie der Dienst die Person
    /// nennt, mit grossem Anfangsbuchstaben. Ohne Token keine Kopfzeile: das
    /// Blatt heisst schon „Zugang“.
    static func healthHeader(hasToken: Bool, name: String?) -> String? {
        guard hasToken else { return nil }
        guard let name, let first = name.first else { return "✓" }
        return "✓ " + first.uppercased() + name.dropFirst()
    }

    // MARK: - Privat-Token

    private var privateSection: some View {
        Section {
            SecureField("fh_private", text: $privateToken)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("privateToken")
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
                 : "Gilt für Essen, To-Do, Wald und das Widget (alles unter fherrmann.com). "
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
                .accessibilityIdentifier("weightToken")
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
