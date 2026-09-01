import SwiftUI

/// Fehlerhinweis ueber dem Inhalt. Bei einem Zugangsproblem steht dort, was
/// zu tun ist - eine blosse Fehlermeldung liesse einen ratlos zuruek.
struct ErrorBanner: View {
    let message: String
    let isAccessProblem: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: isAccessProblem
                  ? "lock.trianglebadge.exclamationmark" : "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
            if isAccessProblem {
                Text("Token im Tab „Zugang“ prüfen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Platzhalter, solange noch nichts geladen ist.
struct LoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Lädt …").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
