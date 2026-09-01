import SwiftUI

/// Gewicht - **Phase 1**: hier wird die WebView durch eine native Ansicht
/// ersetzt (Swift Charts, Eingabe, Ziel). Die Endpunkte stehen in
/// docs/BACKENDS.md, der Plan in docs/STAND.md.
struct WeightTab: View {
    var body: some View {
        WebView(url: Backend.weight.url)
            .ignoresSafeArea(edges: .bottom)
    }
}
