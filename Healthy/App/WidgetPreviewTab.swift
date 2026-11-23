#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Kalorien-Kachel in allen Groessen und Zustaenden, dazu die
/// Schritte-Kacheln des Sperrbildschirms (14.10.) und die Ringe-Komplikation
/// der Uhr (20.11.).
///
/// Der einzige Weg, sie im Simulator anzusehen: `simctl` kann kein Widget auf
/// den Homebildschirm legen. Erreichbar ueber COCKPIT_TAB=widget, nur im
/// Debug-Build. Die Sperrbildschirm-Formen kommen hier nur angenaehert:
/// Apples Accessory-Tachos zeichnen nur in einer echten Kachel.
struct WidgetPreviewTab: View {

    @State private var state: WidgetState = .unreachable(nil)
    @State private var steps = StepsReading(steps: nil, goal: StepsMirror.defaultGoal)
    @State private var strain: StrainDay?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Die grosse Komplikation der Uhr (20.11.) auf schwarzem Grund,
                    // etwa so gross wie das Rechteck auf Modular (46 mm, 40 mm).
                    labelled("Uhr – Ringe, echte Daten und erfunden") {
                        VStack(spacing: 10) {
                            HealthRingsView(rings: liveRings).frame(width: 186, height: 58)
                            HealthRingsView(rings: HealthRings(kcalConsumed: 2420, kcalTarget: 2300, steps: 12_345,
                                                               stepsGoal: 10_000, strain: 15.2, targetStrain: 14.1))
                                .frame(width: 186, height: 58)
                            HealthRingsView(rings: HealthRings(kcalConsumed: nil, kcalTarget: nil, steps: nil,
                                                               stepsGoal: 10_000, strain: nil, targetStrain: 14.1))
                                .frame(width: 150, height: 47)
                        }
                        .padding(10)
                        .background(.black, in: RoundedRectangle(cornerRadius: 18))
                        .environment(\.colorScheme, .dark)
                    }
                    labelled("Sperrbildschirm – Schritte und „Heute“") {
                        HStack(spacing: 12) {
                            StepsCircleView(reading: steps)
                                .frame(width: 72, height: 72)
                            TodayOverviewView(calories: state, steps: steps)
                                .frame(width: 172, height: 72)
                        }
                        .padding(8)
                    }
                    labelled("Schritte – fuenfstellig, ohne Wert") {
                        HStack(spacing: 12) {
                            StepsCircleView(reading: StepsReading(steps: 12_345, goal: 10_000))
                                .frame(width: 72, height: 72)
                            StepsCircleView(reading: StepsReading(steps: nil, goal: 10_000))
                                .frame(width: 72, height: 72)
                            TodayOverviewView(calories: .noAccess,
                                              steps: StepsReading(steps: 12_345, goal: 10_000))
                                .frame(width: 172, height: 72)
                        }
                        .padding(8)
                    }
                    labelled("systemSmall – echte Daten") {
                        CaloriesWidgetView(family: .systemSmall, state: state)
                            .frame(width: 158, height: 158)
                    }
                    labelled("systemMedium – echte Daten") {
                        CaloriesWidgetView(family: .systemMedium, state: state)
                            .frame(width: 338, height: 158)
                    }
                    labelled("Sperrbildschirm – Ring und Rechteck") {
                        HStack(spacing: 12) {
                            CaloriesWidgetView(family: .accessoryCircular, state: state)
                                .frame(width: 72, height: 72)
                            CaloriesWidgetView(family: .accessoryRectangular, state: state)
                                .frame(width: 172, height: 72)
                        }
                        .padding(8)
                    }
                    labelled("ohne Zugang") {
                        CaloriesWidgetView(family: .systemSmall, state: .noAccess)
                            .frame(width: 158, height: 158)
                    }
                    labelled("nicht erreichbar, ohne alten Stand") {
                        CaloriesWidgetView(family: .systemSmall, state: .unreachable(nil))
                            .frame(width: 158, height: 158)
                    }
                }
                .padding()
            }
            .navigationTitle("Kachel")
            .task {
                // Ohne eigenen Cookie: in der App gibt es den gemeinsamen
                // Speicher, den `Access.applyCookies()` beim Start gefuellt hat.
                if let day = try? await FoodAPI().day(.today()) {
                    state = .value(RemainingCalories(day: day))
                }
                steps = await StepsNow.read()
                strain = try? await StrainAPI().today()
            }
        }
    }

    private var liveRings: HealthRings {
        let kcal = state.calories
        return HealthRings(kcalConsumed: kcal?.consumed.kcal, kcalTarget: kcal?.targets.kcal, steps: steps.steps,
                           stepsGoal: steps.goal, strain: strain?.strain, targetStrain: strain?.targetStrain)
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
#endif
