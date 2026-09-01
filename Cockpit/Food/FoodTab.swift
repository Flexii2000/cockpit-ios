import SwiftUI

/// Essen - **Phase 2**: hier wird die WebView durch eine native Ansicht
/// ersetzt (Tagesansicht, Gerichte, Schnellerfassung). Die Endpunkte stehen
/// in docs/BACKENDS.md, der Plan in docs/STAND.md.
struct FoodTab: View {
    var body: some View {
        WebView(url: Backend.food.url)
            .ignoresSafeArea(edges: .bottom)
    }
}
