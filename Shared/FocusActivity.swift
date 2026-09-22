import ActivityKit
import SwiftUI

/// Die Live-Aktivitaet einer Fokus-Session: gross auf dem Sperrbildschirm,
/// klein in der Dynamic Island. Anfang und Ende stehen fest, mehr braucht
/// sie nicht - Countdown und Balken zaehlen von selbst (`timerInterval`),
/// ohne dass die App laufen muss.
///
/// In `Shared/`, weil die Erweiterung sie zeigt und die App sie startet -
/// und der Debug-Tab „Kachel" sie zum Anschauen rendert.
struct FocusActivityAttributes: ActivityAttributes {
    /// Nichts Veraenderliches: was sich aendert, rechnet die Uhr.
    struct ContentState: Codable, Hashable {
        var planted = false
    }

    let start: Date
    let end: Date
    let test: Bool
}

/// Der Sperrbildschirm: ein grosser, blasser Baum hinter Countdown und
/// Balken. Kein eigener Hintergrund - so bleibt das Hintergrundbild
/// sichtbar, das war Felix' Wunsch („fast komplett transparent, dafuer
/// recht gross"). Ist die Session vorbei, ohne dass die App lief, steht
/// „Baum gepflanzt" da, bis die App aufraeumt.
struct FocusActivityView: View {

    let start: Date
    let end: Date
    let test: Bool
    let stale: Bool

    var body: some View {
        ZStack {
            Image(systemName: "tree.fill")
                .font(.system(size: 124))
                .foregroundStyle(.green.opacity(0.32))
                .offset(y: 4)
            VStack(spacing: 8) {
                if stale {
                    Text(test ? "Testbaum fertig" : "Baum gepflanzt")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                } else {
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: 180)
                    ProgressView(timerInterval: start...end, countsDown: false,
                                 label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .tint(.green)
                        .frame(width: 150)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }
}
