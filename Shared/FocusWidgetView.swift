import SwiftUI

/// Was die Fokus-Kachel auf dem Homebildschirm zeigt: die laufende Session
/// mit Countdown - oder, wenn keine laeuft, die Habits. Eine Kachel, zwei
/// Gesichter: waehrend der Session zaehlt sie, sonst zeigt sie, was heute
/// noch offen ist (Felix, 2026-09-22).
struct FocusWidgetState: Sendable, Equatable {
    struct Session: Sendable, Equatable {
        let start: Date
        let end: Date
        let test: Bool
    }

    let session: Session?
    /// Die Habits fuer die Zeit ohne Session - dieselbe Ansicht wie die
    /// Habits-Kachel.
    let habits: HabitsWidgetState

    static let placeholder = FocusWidgetState(
        session: Session(start: Date(), end: Date().addingTimeInterval(1_500), test: false),
        habits: .unreachable)
}

/// Die breite Kachel: links der Baum, rechts gross die Restzeit. Der
/// Countdown zaehlt selbst (`Text(timerInterval:)`), die Kachel muss dafuer
/// nicht neu geladen werden. Kein Balken - der war Felix zu viel. Ohne
/// Session die Habits-Ansicht.
struct FocusWidgetView: View {

    let state: FocusWidgetState

    var body: some View {
        if let session = state.session {
            HStack(spacing: 18) {
                Image(systemName: "tree.fill")
                    .font(.system(size: 66))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(timerInterval: session.start...session.end, countsDown: true)
                        .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(session.test ? "Testbaum · bis \(Self.clock.string(from: session.end))"
                                      : "bis \(Self.clock.string(from: session.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            HabitsWidgetView(family: .systemMedium, state: state.habits)
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
