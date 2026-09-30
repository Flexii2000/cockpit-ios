import SwiftUI

/// „Challenge beendet" (Entwurf S. 17): Podest, Einsatz, wann es weitergeht,
/// „Zur Timeline" | „Gratulieren". Einmal je Person (`dialogs/{id}/seen`).
struct FinishedDialogView: View {
    let dialog: FinishedDialog
    let color: PaletteKey
    let toTimeline: () -> Void
    let congratulate: () -> Void

    @Environment(\.meId) private var meId

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(dialog.isChallenge ? "CHALLENGE BEENDET" : "ZIEL BEENDET")
                        .font(.system(size: 14, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(Ink.ink)
                    Text(dialog.title)
                        .font(.heading(28))
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dialog.podium.isEmpty {
                        Podium(entries: dialog.podium, meId: meId)
                            .padding(.top, 12)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 20)
                .padding(.bottom, dialog.podium.isEmpty ? 24 : 0)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        color.colors.surface
                        CornerCircle(color: color.colors.accent.opacity(0.6), corner: .topLeading, size: 150)
                        CornerCircle(color: color.colors.accent.opacity(0.6), corner: .topTrailing, size: 110, inset: 0.4)
                            .offset(y: 50)
                    }
                }

                VStack(spacing: 16) {
                    if let stake = dialog.stakeText, !stake.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Einsatz")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Ink.muted)
                            Text(stake)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Ink.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Ink.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if let next = dialog.nextText, !next.isEmpty {
                        Text(next)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.muted)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 12) {
                        Button("Zur Timeline", action: toTimeline)
                            .buttonStyle(OutlineButtonStyle(height: 52))
                            .accessibilityIdentifier("dialogTimeline")
                        Button("Gratulieren", action: congratulate)
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("dialogCongratulate")
                    }
                }
                .padding(20)
                .background(Ink.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 22)
        }
        .accessibilityIdentifier("finishedDialog")
    }
}

/// Zweiter links, Erster in der Mitte (hoch, in Tinte), Dritter rechts.
struct Podium: View {
    let entries: [PodiumEntry]
    let meId: String?

    var body: some View {
        let byRank = entries.sorted { $0.rank < $1.rank }
        let order: [PodiumEntry] = [byRank.dropFirst().first, byRank.first, byRank.dropFirst(2).first].compactMap { $0 }
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(order) { entry in
                column(entry, first: entry.id == byRank.first?.id)
            }
        }
    }

    private func column(_ entry: PodiumEntry, first: Bool) -> some View {
        VStack(spacing: 8) {
            Text(entry.person.label(me: meId))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
            VStack(spacing: 2) {
                Text(entry.scoreText ?? "")
                    .font(.figure(first ? 32 : 26))
                Text("Platz \(entry.rank)")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(first ? Ink.onInk : Ink.ink)
            .frame(maxWidth: .infinity)
            .frame(height: first ? 108 : (entry.rank == 2 ? 74 : 56))
            .background(first ? Ink.ink : Ink.surface,
                        in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}
