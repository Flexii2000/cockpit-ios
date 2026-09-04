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


/// „Offline - Stand von gestern, 2 Aenderungen warten" - ueber dem Inhalt
/// eines Tabs, sobald etwas davon zutrifft. Sonst nichts.
///
/// Das Datum ist der Punkt: ein alter Stand, der wie ein aktueller aussieht,
/// ist schlimmer als gar keiner.
struct OfflineBanner: View {

    let backend: Backend

    private var status: OfflineStatus { OfflineStatus.shared }

    var body: some View {
        let stale = status.staleSince[backend]
        let pending = status.pending
        if stale != nil || pending > 0 || status.lastOutboxError != nil {
            VStack(alignment: .leading, spacing: 2) {
                Label(headline(stale: stale, pending: pending),
                      systemImage: stale != nil ? "wifi.slash" : "clock.arrow.circlepath")
                    .font(.footnote.weight(.medium))
                if let error = status.lastOutboxError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
            .accessibilityIdentifier("offlineBanner")
        }
    }

    private func headline(stale: Date?, pending: Int) -> String {
        var parts: [String] = []
        if let stale {
            parts.append("Offline – Stand von " + Self.stamp.string(from: stale))
        }
        if pending > 0 {
            parts.append(pending == 1 ? "1 Änderung wartet auf Netz"
                                      : "\(pending) Änderungen warten auf Netz")
        }
        return parts.joined(separator: " · ")
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM., HH:mm"
        return formatter
    }()
}
