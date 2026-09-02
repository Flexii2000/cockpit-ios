import LocalAuthentication
import SwiftUI

/// Die Sperre vor dem Finanzen-Tab.
///
/// Sie schuetzt die **Anzeige**, nicht den Zugang: hinter dem Tab steht eine
/// WKWebView mit einer angemeldeten Sitzung, die sieben Tage haelt. Wer das
/// Handy in die Hand bekommt, soll nicht mit einem Wisch die Kontostaende
/// sehen - deshalb Face ID davor.
@MainActor
@Observable
final class FinanceLock {

    private(set) var isUnlocked = false
    private(set) var lastFailure: String?

    /// Laeuft gerade eine Abfrage?
    ///
    /// Waehrend `evaluatePolicy` den Dialog zeigt, meldet iOS die App als
    /// **inaktiv**. Wer darauf hin zusperrt, schliesst mitten in die eigene
    /// Abfrage hinein - und wenn die Ansicht daraufhin erneut fragt, oeffnet
    /// sich der Dialog sofort wieder. Der Tab wird dann nie sichtbar, und der
    /// einzige Ausweg ist der App-Wechsler.
    private var isAuthenticating = false

    /// Ob es ueberhaupt etwas zu sperren gibt.
    ///
    /// Ohne Code und ohne Biometrie kann sich niemand ausweisen - dann waere
    /// eine Sperre kein Schutz, sondern eine Aussperrung.
    var isAvailable: Bool {
        #if DEBUG
        // Der Simulator hat standardmaessig kein Gesicht hinterlegt, und
        // Freigeben laesst sich nur ueber das Menue der Simulator-App.
        // COCKPIT_NO_LOCK=1 nimmt die Sperre fuer Aufnahmen heraus.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_LOCK"] == "1" { return false }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_FORCE_LOCK"] == "1" { return true }
        #endif
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func unlock() async {
        guard !isUnlocked else { return }
        #if DEBUG
        // Im Simulator gibt es kein Gesicht, das man vorzeigen koennte -
        // ohne diesen Schalter waere der Sperrbildschirm nie aufzunehmen.
        if ProcessInfo.processInfo.environment["COCKPIT_FORCE_LOCK"] == "1" { return }
        #endif
        guard isAvailable else {
            // Nichts zu prüfen, also auch nichts zu sperren.
            isUnlocked = true
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        do {
            // `deviceOwnerAuthentication` und nicht `...WithBiometrics`: bei
            // Maske, Dunkelheit oder drei Fehlversuchen fuehrt der Weg dann
            // ueber den Geraetecode weiter. Die strengere Variante sperrt in
            // genau diesen Faellen aus - und die Sperre soll den Blick ueber
            // die Schulter verhindern, nicht den Besitzer aussperren.
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Damit deine Finanzen nicht offen daliegen.")
            lastFailure = nil
        } catch let error as LAError where error.code == .userCancel
                                        || error.code == .appCancel
                                        || error.code == .systemCancel {
            // Abbrechen ist kein Fehler - es bleibt schlicht zu.
            lastFailure = nil
        } catch {
            lastFailure = error.localizedDescription
        }
    }

    /// Beim Verlassen der App wieder zu. Sonst schuetzt die Sperre nur den
    /// ersten Blick und danach nie wieder.
    ///
    /// Nicht waehrend einer laufenden Abfrage: der Face-ID-Dialog selbst macht
    /// die App inaktiv, und ein Zusperren an dieser Stelle laesst den Dialog
    /// endlos wiederkommen.
    func lock() {
        guard !isAuthenticating else { return }
        isUnlocked = false
    }
}
