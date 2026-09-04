import Foundation

/// Haelt den Notenstand und die Annahmen.
@MainActor
@Observable
final class GradesStore {

    private let api = GradesAPI()

    private(set) var overview: GradesOverview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Zugang fehlt oder stimmt nicht - dann hilft nur der Zugang-Tab.
    private(set) var needsSetup = false

    /// Angenommene Noten fuer offene Module, Modulname → Note.
    ///
    /// Sie liegen **hier** und nicht auf dem Server: es sind Gedankenspiele,
    /// keine Daten. Die Weboberflaeche haelt sie in ihrer Sitzung; waeren es
    /// dieselben, wuerde ein Tippen im Handy den Browser-Tab umschreiben, den
    /// Felix nebenbei offen hat.
    private(set) var assumptions: [String: Double] = [:]

    private static let assumptionsKey = "grades.assumptions"
    private static let registeredTokenKey = "grades.registeredPushToken"

    init() {
        assumptions = UserDefaults.standard
            .dictionary(forKey: Self.assumptionsKey) as? [String: Double] ?? [:]
    }

    // MARK: - Laden

    /// Holt den Stand. Meldet sich unterwegs an, wenn die Sitzung abgelaufen ist.
    func load(access: Access, lock: BiometricLock) async {
        guard access.isGradesConfigured else {
            needsSetup = true
            errorMessage = "Kein Zugang zur Notenübersicht."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await fetch()
        } catch {
            // Die Sitzung haelt sieben Tage. Laeuft sie ab, ist das kein
            // Fehler, den jemand sehen muesste - die App hat Benutzer und
            // Passwort und meldet sich einfach neu an.
            guard GradesAccessProblem.from(error) == .notSignedIn else {
                report(error)
                return
            }
            do {
                try await signIn(access: access, lock: lock)
                try await fetch()
            } catch {
                report(error)
            }
        }
        if overview != nil { await registerForPushIfNeeded() }
    }

    private func fetch() async throws {
        overview = assumptions.isEmpty
            ? try await api.overview()
            : try await api.overview(assumptions: assumptions)
        errorMessage = nil
        needsSetup = false
    }

    private func signIn(access: Access, lock: BiometricLock) async throws {
        // Der Kontext hat seine Face-ID-Pruefung hinter sich (der Tab ist ja
        // offen), deshalb kommt das Passwort ohne zweite Abfrage heraus.
        guard let password = access.gradesPassword(context: lock.context),
              let user = access.gradesUser else {
            needsSetup = true
            throw GradesStoreError.noPassword
        }
        do {
            try await api.login(user: user, password: password)
        } catch {
            if GradesAccessProblem.from(error) == .notSignedIn {
                // Anmeldung abgelehnt: das hinterlegte Passwort stimmt nicht
                // mehr. Weiterprobieren hiesse, es bei jedem Oeffnen erneut
                // zu versuchen.
                needsSetup = true
                throw GradesStoreError.wrongCredentials
            }
            throw error
        }
    }

    private func report(_ error: Error) {
        switch GradesAccessProblem.from(error) {
        case .noDeviceToken:
            needsSetup = true
            errorMessage = "Kein Zugang – Geräte-Token im Zugang-Tab prüfen."
        case .wrongCredentials, .notSignedIn:
            needsSetup = true
            errorMessage = "Anmeldung abgelehnt – Benutzer und Passwort prüfen."
        case nil:
            if let problem = error as? GradesStoreError {
                errorMessage = problem.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Annahmen

    /// Setzt oder loescht eine angenommene Note und rechnet neu.
    func setAssumption(_ grade: Double?, for module: String) async {
        if let grade {
            assumptions[module] = grade
        } else {
            assumptions.removeValue(forKey: module)
        }
        persistAssumptions()
        await recompute()
    }

    func clearAssumptions() async {
        assumptions.removeAll()
        persistAssumptions()
        await recompute()
    }

    private func persistAssumptions() {
        UserDefaults.standard.set(assumptions, forKey: Self.assumptionsKey)
    }

    /// Neu rechnen lassen. Ohne Anmeldeversuch: wer gerade Annahmen tippt, hat
    /// den Tab offen und damit eine Sitzung.
    private func recompute() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await fetch()
        } catch {
            report(error)
        }
    }

    // MARK: - Push

    /// Meldet die Push-Kennung an, sobald eine Sitzung steht.
    ///
    /// Nicht beim Start wie beim Kalorienzaehler: dieser Endpunkt liegt hinter
    /// der Anmeldung, und die gibt es erst, wenn Felix den Tab aufmacht. Wer
    /// die Noten nie ansieht, bekommt dafuer auch keine Meldung ueber sie.
    private func registerForPushIfNeeded() async {
        guard let token = Notifications.deviceToken else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.registeredTokenKey) != token else { return }
        do {
            try await api.registerDevice(token: token)
            defaults.set(token, forKey: Self.registeredTokenKey)
        } catch {
            // Kein Grund, den Notenstand deshalb nicht zu zeigen.
            print("Noten-Push nicht angemeldet: \(error.localizedDescription)")
        }
    }
}

enum GradesStoreError: LocalizedError {
    case noPassword
    case wrongCredentials

    var errorDescription: String? {
        switch self {
        case .noPassword:
            "Passwort nicht lesbar – im Zugang-Tab neu hinterlegen."
        case .wrongCredentials:
            "Anmeldung abgelehnt – Passwort im Zugang-Tab prüfen."
        }
    }
}
