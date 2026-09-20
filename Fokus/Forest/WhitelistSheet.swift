import FamilyControls
import SwiftUI

/// Apples Auswahlblatt fuer die Apps, die waehrend einer Session offen
/// bleiben. Die App sieht nur Token, keine Namen - so will es Apple.
struct WhitelistSheet: View {

    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Der Schild gilt fuer alle Kategorien - auch fuer die Fokus-App
                // selbst. Wer den Wald waehrend der Session sehen will, nimmt
                // sie hier mit dazu.
                Text("Fokus selbst mit auswählen, sonst ist auch der Wald gesperrt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                FamilyActivityPicker(selection: $selection)
            }
            .navigationTitle("Erlaubte Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
