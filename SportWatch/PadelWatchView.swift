import SwiftUI
import WatchKit

/// Ein Padel-Match auf der Uhr (Felix, 23.10.): links die Steuerung (Beenden, Zurueck), in der
/// Mitte die Punkte, daneben Puls und kcal, ganz rechts die Musik.
struct PadelWatchView: View {

    enum Page: Hashable { case controls, score, metrics, music }

    @State private var page = PadelWatchView.firstPage
    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsPage(undo: { workout.undoPoint() }).tag(Page.controls)
            PadelScorePage().tag(Page.score)
            WorkoutMetricsPage().tag(Page.metrics)
            NowPlayingView().tag(Page.music)
        }
        .tabViewStyle(.page)
    }

    private static var firstPage: Page {
        #if DEBUG
        // Fuer Aufnahmen: der Uhren-Simulator kann nicht blaettern.
        if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "padel-metrics" { return .metrics }
        #endif
        return .score
    }
}

/// Zwei Haelften zum Antippen, wie das Feld von unserer Seite aus (Felix, 23.10.): oben die
/// anderen, unten wir. Je Seite die Punkte gross, darueber die Saetze und die Spiele im laufenden
/// Satz. Der Ball steht beim Spieler, der aufschlaegt - links oder rechts, Antippen tauscht.
/// Dazwischen „Zurueck“ fuer einen versehentlich gezaehlten Punkt.
struct PadelScorePage: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        if let match = workout.padel {
            VStack(spacing: 3) {
                half(.them, match.score)
                middle(match.score, canUndo: !match.history.isEmpty)
                half(.us, match.score)
            }
            // Unten liegen die Seitenpunkte, und die runden Ecken des Displays schneiden an, was
            // bis an den Rand reicht (Felix, 23.10.: „unten abgeschnitten“).
            .padding(.bottom, 2)
        }
    }

    private func half(_ side: PadelSide, _ score: PadelScore) -> some View {
        let serving = score.server == side && score.winner == nil
        return Button {
            workout.point(for: side)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(side == .us ? "Wir" : "Die")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    ForEach(Array(score.sets.enumerated()), id: \.offset) { _, set in
                        Text("\(side == .us ? set.us : set.them)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(set.winner == side ? .primary : .secondary)
                    }
                    if score.winner == nil {
                        Text("\(score.games[side])")
                            .font(.caption.monospacedDigit().weight(.bold))
                    }
                }
                Text(points(side, score))
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((side == .us ? Color.green : Color.blue).opacity(0.24),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(score.winner != nil)
        .accessibilityLabel(side == .us ? "Punkt für uns" : "Punkt für die anderen")
        .overlay(alignment: score.servingPlayer == .left ? .leading : .trailing) {
            if serving { ball(score.servingPlayer) }
        }
    }

    /// Der Ball als eigener Knopf ueber der Haelfte - gross genug fuer den Finger, damit ein Tipp
    /// daneben ein Punkt bleibt.
    private func ball(_ player: PadelPlayer) -> some View {
        Button {
            workout.switchServingPlayer()
        } label: {
            Image(systemName: "tennisball.fill")
                .font(.system(size: 13))
                .foregroundStyle(.yellow)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player == .left ? "Aufschlag links" : "Aufschlag rechts")
        .accessibilityHint("Tauscht den Spieler")
    }

    private func points(_ side: PadelSide, _ score: PadelScore) -> String {
        guard let winner = score.winner else { return score.pointLabel(side) }
        return winner == side ? "✓" : ""
    }

    /// Links „Zurueck“, in der Mitte, was gerade besonders ist: der entscheidende Punkt, ein
    /// Tie-Break, das Ende.
    private func middle(_ score: PadelScore, canUndo: Bool) -> some View {
        let text: String? = score.winner != nil ? "Match vorbei"
            : score.isTieBreak ? "Tie-Break"
            : score.isDecidingPoint ? score.rule.label
            : nil
        return ZStack {
            Text(text ?? " ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.yellow)
            HStack {
                Button {
                    workout.undoPoint()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2.weight(.bold))
                        .frame(width: 38, height: 22)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.4)
                .accessibilityLabel("Zurück")
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
    }
}
