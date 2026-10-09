import SwiftUI

/// Schlafbedarf aendern - ab hier bringt mehr Schlaf in der Recovery nichts
/// mehr. In Viertelstunden von 4 bis 12 Stunden, wie der Dienst es annimmt.
/// Gilt auch rueckwirkend: der Dienst rechnet jeden Score neu.
struct RecoverySettingsSheet: View {

    let store: RecoveryStore
    @Environment(\.dismiss) private var dismiss

    @State private var minutes = 480
    @State private var isSaving = false

    private static let choices = Array(stride(from: RecoverySettings.range.lowerBound,
                                              through: RecoverySettings.range.upperBound,
                                              by: RecoverySettings.step))

    var body: some View {
        NavigationStack {
            Form {
                Picker("Schlafbedarf", selection: $minutes) {
                    ForEach(Self.choices, id: \.self) { value in
                        Text(RecoveryFormat.hoursMinutes(Double(value))).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                if let error = store.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Schlafbedarf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            if await store.updateSleepNeed(minutes) { dismiss() }
                        }
                    }
                    .disabled(isSaving || minutes == store.sleepNeedMinutes)
                }
            }
            .onAppear {
                // Auf die naechste Viertelstunde - ein im Web gesetzter Wert
                // muss nicht auf dem Raster liegen.
                let current = store.sleepNeedMinutes ?? 480
                minutes = Self.choices.min { abs($0 - current) < abs($1 - current) } ?? 480
            }
        }
        .presentationDetents([.medium])
    }
}
