import SwiftUI

/// Das Morgen-Briefing ganz oben im Dashboard (Vertrag §5): nur der Text, ohne
/// Ueberschrift - zwei bis drei Saetze, die fuer sich stehen.
struct BriefingCard: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardCard()
            .accessibilityIdentifier("briefingCard")
    }
}
