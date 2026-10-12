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

/// Die kleine Uhr an einem Haken (To-Do, Einkaufsliste), solange die Aenderung
/// auf Netz wartet. Der Haken selbst zeigt schon den neuen Stand - die Uhr sagt
/// nur, dass der Dienst ihn noch nicht hat.
struct WaitingBadge: View {
    var body: some View {
        Image(systemName: "clock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(2)
            .background(Color.orange, in: Circle())
            .offset(x: 4, y: 4)
            .accessibilityHidden(true)
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
///
/// Gezaehlt wird nur, was zu den Diensten des Tabs gehoert - im alten
/// Postausgang und in der Warteschlange der sofort gezeigten Aenderungen
/// (`PendingChanges`). Frueher sagte der Einkaufs-Tab „2 Aenderungen warten",
/// weil im Essen-Tab zwei Eintraege auf Netz warteten.
struct OfflineBanner: View {

    /// Die Dienste, deren Stand der Tab zeigt. Mehrere, wo ein Tab mehrere
    /// zeigt (das Dashboard in Healthy: Essen und Gewicht) - eine Leiste je
    /// Dienst zaehlte die wartenden Aenderungen doppelt.
    let backends: [Backend]

    init(backend: Backend) {
        backends = [backend]
    }

    init(backends: [Backend]) {
        self.backends = backends
    }

    private var status: OfflineStatus { OfflineStatus.shared }
    private var queue: PendingChanges { PendingChanges.shared }

    var body: some View {
        // Der aelteste Stand zaehlt: so alt ist das Bild mindestens.
        let stale = backends.compactMap { status.staleSince[$0] }.min()
        let pending = backends.reduce(0) { $0 + (status.pendingByBackend[$1] ?? 0) + queue.count(for: $1) }
        // Waehrend gesendet wird, keine Zahl: online ist das eine Frage von
        // Millisekunden, und die Leiste blitzte bei jedem Haken auf.
        let sending = backends.contains { queue.laneState[$0] == .sending }
        let shownPending = sending && stale == nil ? 0 : pending
        let rejection = backends.lazy.compactMap { queue.lastRejection[$0] }.first
        if stale != nil || shownPending > 0 || status.lastOutboxError != nil || rejection != nil {
            VStack(alignment: .leading, spacing: 2) {
                if stale != nil || shownPending > 0 {
                    Label(headline(stale: stale, pending: shownPending),
                          systemImage: stale != nil ? "wifi.slash" : "clock.arrow.circlepath")
                        .font(.footnote.weight(.medium))
                }
                if let error = rejection ?? status.lastOutboxError {
                    HStack(alignment: .firstTextBaseline) {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Spacer(minLength: 4)
                        if rejection != nil {
                            Button {
                                for backend in backends { queue.dismissRejection(backend) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Meldung schließen")
                        }
                    }
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
            let count = pending == 1 ? "1 Änderung wartet" : "\(pending) Änderungen warten"
            let states = backends.compactMap { queue.laneState[$0] }
            if states.contains(.accessDenied) {
                parts.append(count + " – kein Zugang, Token prüfen")
            } else if states.contains(.serverDown) {
                parts.append(count + " – Dienst antwortet nicht")
            } else {
                parts.append(count + " auf Netz")
            }
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
