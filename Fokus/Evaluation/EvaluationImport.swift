import Foundation

/// Fokus uebernimmt die Evaluation, die Healthy angeboten hat
/// (`EvaluationHandoff`, 14.10.).
///
/// Nichts wird ueberschrieben, was Antworten hat, und nichts verworfen: Hat Fokus
/// schon eigene Antworten (etwa weil Fokus vor dem neuen Healthy lief und dort
/// schon jemand geantwortet hat), landet die Datei aus Healthy daneben als
/// `evaluation-healthy.json`, und eine Meldung sagt es. Eine Fokus-Datei nur mit
/// Fragen wird ersetzt - sie ist ein frischer Anfang, kein Stand.
enum EvaluationImport {

    enum Outcome: Equatable, Sendable {
        /// Nichts angeboten (der Normalfall nach dem Umzug).
        case nothing
        /// Gerade nicht moeglich (Datei gesperrt, Schreiben gescheitert) - der
        /// Eintrag bleibt, beim naechsten Start noch einmal.
        case later
        /// Der Eintrag ist keine Evaluation - er bleibt liegen, Healthy behaelt das Original.
        case broken
        case imported
        case keptBoth
    }

    static let sideFileName = "evaluation-healthy.json"

    static func run(file: URL = EvaluationStore.defaultFile,
                    slot: EvaluationHandoff.Slot = .keychain) -> Outcome {
        guard let bytes = slot.read(EvaluationHandoff.handoffKey) else { return .nothing }
        guard let incoming = try? JSONDecoder().decode(EvaluationData.self, from: bytes) else { return .broken }
        let existing: EvaluationData?
        do {
            existing = try EvaluationStore.read(file)
        } catch {
            // Da, aber nicht lesbar - etwa direkt nach dem Start bei gesperrtem
            // Geraet. Lieber spaeter, als blind daneben schreiben.
            return .later
        }

        let target: URL
        let outcome: Outcome
        if let existing, existing.hasAnswers, existing != incoming {
            target = file.deletingLastPathComponent().appendingPathComponent(sideFileName)
            outcome = .keptBoth
        } else {
            target = file
            outcome = .imported
        }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bytes.write(to: target, options: [.atomic, .completeFileProtection])
            guard try Data(contentsOf: target) == bytes else { return .later }
        } catch {
            return .later
        }
        // Erst quittieren, dann wegraeumen: scheitert die Quittung, bietet Healthy
        // beim naechsten Start noch einmal an, und derselbe Stand landet noch
        // einmal am selben Ort - das schadet nicht.
        guard slot.write(Data(EvaluationHandoff.digest(bytes).utf8), EvaluationHandoff.importedKey) else {
            return .later
        }
        slot.delete(EvaluationHandoff.handoffKey)
        return outcome
    }
}

/// Zaehlt die gelungenen Uebernahmen - ein offener Tab laedt dann neu.
@MainActor
@Observable
final class EvaluationImportState {
    static let shared = EvaluationImportState()
    private(set) var generation = 0
    private init() {}

    /// Uebernimmt, was Healthy anbietet, und sagt Bescheid, wenn es daneben liegt.
    func runIfOffered() async {
        #if DEBUG
        // Vorfuehrdaten und UI-Tests fassen weder die echte Datei noch den
        // Eintrag an - er gehoert dem echten Umzug.
        let environment = ProcessInfo.processInfo.environment
        if environment["COCKPIT_EVALUATION_DEMO"] == "1" || environment["COCKPIT_EVALUATION_SCRATCH"] == "1" { return }
        #endif
        switch EvaluationImport.run() {
        case .imported:
            generation += 1
            await EvaluationReminder.refresh()
        case .keptBoth:
            generation += 1
            NoticeCenter.shared.show("Evaluation aus Healthy liegt daneben (\(EvaluationImport.sideFileName)).",
                                     isInfo: true)
        case .nothing, .later, .broken:
            break
        }
    }
}

extension EvaluationData {
    /// Ob irgendein Tag eine Antwort hat - eine Datei nur mit Fragen ist ein Anfang, kein Stand.
    var hasAnswers: Bool { days.contains { !$0.values.isEmpty } }
}
