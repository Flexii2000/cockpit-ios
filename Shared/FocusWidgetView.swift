import SwiftUI

/// Was die Fokus-Kachel auf dem Homebildschirm zeigt: die laufende Session
/// mit Countdown - oder, wenn keine laeuft, den Stand von heute gegen das
/// Tagesziel. Die Habits, die hier bis zum Umzug nach coHabit standen, zeigt
/// jetzt die coHabit-Kachel.
struct FocusWidgetState: Sendable, Equatable {
    struct Session: Sendable, Equatable {
        let start: Date
        let end: Date
        let test: Bool
    }

    let session: Session?
    /// Fokus-Minuten von heute - aus der App-Gruppe, die App legt sie nach
    /// jedem Laden ab (`FocusHandoff.saveToday`).
    let todayMinutes: Int
    let goal: Int?

    static let placeholder = FocusWidgetState(
        session: Session(start: Date(), end: Date().addingTimeInterval(1_500), test: false),
        todayMinutes: 0, goal: nil)
}

/// Die breite Kachel: links der Baum, rechts gross die Restzeit. Der
/// Countdown zaehlt selbst (`Text(timerInterval:)`), die Kachel muss dafuer
/// nicht neu geladen werden. Kein Balken - der war Felix zu viel.
struct FocusWidgetView: View {

    let state: FocusWidgetState

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "tree.fill")
                .font(.system(size: 66))
                .foregroundStyle(state.session == nil ? Color.green.opacity(0.55) : .green)
            VStack(alignment: .leading, spacing: 4) {
                if let session = state.session {
                    Text(timerInterval: session.start...session.end, countsDown: true)
                        .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(session.test ? "Testbaum · bis \(Self.clock.string(from: session.end))"
                                      : "bis \(Self.clock.string(from: session.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.goal.map { FocusMinutes.progress(state.todayMinutes, goal: $0) }
                         ?? FocusMinutes.hours(state.todayMinutes) + " h")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(reached ? Color.green : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("heute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var reached: Bool {
        guard let goal = state.goal, goal > 0 else { return false }
        return state.todayMinutes >= goal
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
