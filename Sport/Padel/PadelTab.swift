import SwiftUI

/// Padel - die Autobuchung bei Playtomic (fherrmann.com/padel), nativ (Felix, 23.10.).
struct PadelTab: View {
    var body: some View {
        NavigationStack {
            LoadingPlaceholder()
                .navigationTitle("Padel")
                .toolbar { ToolbarItem(placement: .topBarLeading) { AccessButton() } }
        }
    }
}
