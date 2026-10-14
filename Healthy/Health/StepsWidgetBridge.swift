import Foundation
import WidgetKit

/// Reicht die Schritte von heute und das Tagesziel an die Sperrbildschirm-
/// Kacheln (14.10.) - ueber den geteilten Schluesselbund (`StepsMirror`).
///
/// Neu gezeichnet wird nur, wenn sich etwas geaendert hat: WidgetKit zaehlt
/// jedes Neuladen gegen ein Tagesbudget.
@MainActor
enum StepsWidgetBridge {

    static func mirror(steps: Int) {
        if StepsMirror.save(steps: steps) { reload() }
    }

    static func mirror(goal: Int) {
        if StepsMirror.saveGoal(goal) { reload() }
    }

    /// Beim Start und zurueck im Vordergrund: Schritte aus Health (der Blick
    /// spiegelt selbst), das Ziel vom Weight Tracker, solange noch keins
    /// abgelegt ist - danach haelt es der Gewicht-Tab aktuell, wo es sich aendert.
    static func refresh() async {
        _ = await HealthSync.shared.todaySteps()
        if Keychain.read(StepsMirror.goalKey) == nil,
           let goal = try? await WeightAPI().stepsGoal() {
            mirror(goal: goal.stepsPerDay)
        }
    }

    private static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.steps)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
    }
}
