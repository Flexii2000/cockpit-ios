import SwiftUI

/// Der Rahmen aller Karten: dieselbe Flaeche wie die Kacheln im Gewicht-Tab. In Core, seit der
/// Gym-Tab nach Sport gezogen ist (23.10.) - Dashboard und Gym nutzen dieselben Karten.
private struct DashboardCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func dashboardCard() -> some View { modifier(DashboardCardStyle()) }
}
