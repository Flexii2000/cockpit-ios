import Foundation

/// Face ID vor dem Evaluation-Tab - mit fuenf Minuten Frist.
///
/// Anders als in Vault geht die Sperre nicht sofort beim Verlassen zu: wer
/// kurz in einen anderen Tab oder eine andere App wechselt, soll beim
/// Zurueckkommen nicht wieder fragen muessen. Die Frist laeuft ab dem Moment,
/// in dem man den Tab oder die App verlaesst (Felix, 04.10.); wer zurueckkommt,
/// bevor sie um ist, findet den Tab offen, und das naechste Verlassen zaehlt
/// von vorn.
///
/// Gemessen mit `ContinuousClock`: die laeuft weiter, waehrend das iPhone
/// schlaeft, und springt nicht mit, wenn jemand die Uhrzeit verstellt.
@MainActor
@Observable
final class EvaluationLock {

    static let grace: Duration = .seconds(5 * 60)

    let biometric: BiometricLock

    /// Wann der Tab zuletzt aus dem Blick ging - `nil`, solange er zu sehen ist.
    private(set) var leftAt: ContinuousClock.Instant?

    @ObservationIgnored private let now: () -> ContinuousClock.Instant

    init(biometric: BiometricLock = BiometricLock(reason: "Damit deine Evaluation nicht offen daliegt."),
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.biometric = biometric
        self.now = now
    }

    var isUnlocked: Bool { biometric.isUnlocked }

    /// Tab oder App verlassen. Nur der erste Wechsel zaehlt: wer vom Tab in
    /// einen anderen geht und von dort aus der App, hat den Tab beim ersten
    /// Schritt verlassen.
    func leave() {
        if leftAt == nil { leftAt = now() }
    }

    /// Der Tab ist wieder zu sehen. Ist die Frist um, geht die Sperre zu.
    /// - Returns: ob sie dabei zugegangen ist.
    @discardableResult
    func back() -> Bool {
        defer { leftAt = nil }
        guard let leftAt, now() - leftAt >= Self.grace else { return false }
        biometric.lock()
        return true
    }

    /// Wechsel in den Tab: erst die Frist pruefen, dann - falls zu - gleich
    /// fragen. Ein zusaetzlicher Tipp auf „Entsperren“ waere ein Klick, der
    /// nichts entscheidet.
    func show() async {
        back()
        await biometric.unlock()
    }

    /// Zurueck in die App, der Tab war offen: nur fragen, wenn die Frist eben
    /// abgelaufen ist. Der Face-ID-Dialog selbst macht die App kurz inaktiv -
    /// wer ihn abbricht, kaeme sonst sofort wieder in denselben Dialog, und
    /// der Tab waere nie zu sehen. Bleibt er zu, steht dort „Entsperren“.
    func returnToForeground() async {
        if back() { await biometric.unlock() }
    }
}
