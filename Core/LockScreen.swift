import SwiftUI

/// Der Bildschirm vor einem gesperrten Tab - in Vault vor der ganzen App, in
/// Healthy vor der Evaluation. In `Core/`, weil zwei Apps ihn brauchen.
struct LockScreen: View {

    let title: String
    let failure: String?
    let unlock: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Entsperren") {
                Task { await unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
