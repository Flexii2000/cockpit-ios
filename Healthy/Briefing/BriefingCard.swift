import SwiftUI

/// Das Morgen-Briefing ganz oben im Dashboard (Vertrag §5): nur der Text, ohne
/// Ueberschrift - zwei bis drei Saetze, die fuer sich stehen.
struct BriefingCard: View {

    let text: String
    /// Ein neuer Text entsteht (nach dem Runterwischen): der alte steht
    /// blasser da, oben rechts ein kleiner Kreisel.
    var rewriting = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(rewriting ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, rewriting ? 22 : 0)
            .overlay(alignment: .topTrailing) {
                if rewriting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Wird neu geschrieben")
                }
            }
            .animation(.default, value: rewriting)
            .dashboardCard()
            .accessibilityIdentifier("briefingCard")
    }
}
