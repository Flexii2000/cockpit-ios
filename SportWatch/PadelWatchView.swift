import SwiftUI
import WatchKit

/// Ein Padel-Match auf der Uhr (Felix, 23.10.): links die Steuerung (Beenden, Zurueck), in der
/// Mitte die Punkte, daneben Puls und kcal, ganz rechts die Musik.
struct PadelWatchView: View {

    enum Page: Hashable { case controls, score, metrics, music }

    @State private var page = Page.score
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
}

/// Zwei Haelften zum Antippen: oben wir, unten die anderen. Je Seite die Punkte gross, daneben
/// die Saetze und die Spiele im laufenden Satz; der Ball zeigt, wer aufschlaegt.
struct PadelScorePage: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        if let score = workout.padel?.score {
            VStack(spacing: 3) {
                half(.us, score)
                badge(score)
                half(.them, score)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func half(_ side: PadelSide, _ score: PadelScore) -> some View {
        Button {
            workout.point(for: side)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.yellow)
                        .opacity(score.server == side && score.winner == nil ? 1 : 0)
                        .accessibilityLabel(score.server == side ? "Aufschlag" : "")
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
    }

    private func points(_ side: PadelSide, _ score: PadelScore) -> String {
        guard let winner = score.winner else { return score.pointLabel(side) }
        return winner == side ? "✓" : ""
    }

    /// Was gerade besonders ist: der entscheidende Punkt, ein Tie-Break, das Ende.
    @ViewBuilder
    private func badge(_ score: PadelScore) -> some View {
        let text: String? = score.winner != nil ? "Match vorbei"
            : score.isTieBreak ? "Tie-Break"
            : score.isDecidingPoint ? score.rule.label
            : nil
        Text(text ?? " ")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.yellow)
            .frame(height: 12)
    }
}
