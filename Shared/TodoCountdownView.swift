import SwiftUI
import WidgetKit

// Die Countdown-Kachel einer Aufgabe in Fokus (seit 17.11.): klein auf dem
// Homebildschirm, rund, rechteckig und als Zeile auf dem Sperrbildschirm. Nur
// die Zahl, kein Ring - Felix' Wahl. `day` ist der Tag des Eintrags in der
// Zeitleiste, nicht der Tag, an dem geladen wurde.

/// Klein: Titel, gross die Tage, unten Wochentag und Datum.
struct TodoCountdownSmallView: View {

    let state: TodoCountdownWidgetState
    let day: CalendarDate

    var body: some View {
        if case .countdown(let todo) = state {
            countdown(todo, phase: todo.phase(on: day))
        } else {
            Text(state.message ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func countdown(_ todo: TodoCountdown, phase: TodoCountdown.Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(todo.title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            if let figure = phase.figure {
                Text(figure)
                    .font(.system(size: phase == .today ? 40 : 52, weight: .semibold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(phase.isOverdue ? Color.red : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.green)
            }
            if let caption = phase.caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(phase.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            if let date = todo.dateText(today: day) {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Rechteckig auf dem Sperrbildschirm: Titel, Tage, Datum.
struct TodoCountdownRectangularView: View {

    let state: TodoCountdownWidgetState
    let day: CalendarDate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .countdown(let todo) = state {
                Text(todo.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(todo.phase(on: day).line)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                if let date = todo.dateText(today: day) {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(state.message ?? "")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Rund auf dem Sperrbildschirm: nur Zahl und Einheit.
struct TodoCountdownCircularView: View {

    let state: TodoCountdownWidgetState
    let day: CalendarDate

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if case .countdown(let todo) = state {
            let compact = todo.phase(on: day).compact
            if let figure = compact.figure {
                VStack(spacing: -2) {
                    Text(figure)
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let unit = compact.unit {
                        Text(unit)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
            }
        } else {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .medium))
        }
    }
}

/// Die Zeile ueber der Uhr: „Klausur in 60 Tagen“.
struct TodoCountdownInlineView: View {

    let state: TodoCountdownWidgetState
    let day: CalendarDate

    var body: some View {
        Label(text, systemImage: "hourglass")
    }

    private var text: String {
        if case .countdown(let todo) = state {
            return todo.phase(on: day).sentence(todo.title)
        }
        return state.message ?? ""
    }
}

private extension TodoCountdown.Phase {
    var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }
}
