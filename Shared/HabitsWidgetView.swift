import SwiftUI
import WidgetKit

/// Was die Habits-Kachel zeigt - und ob man ihr trauen darf.
enum HabitsWidgetState: Equatable, Sendable {
    case noAccess
    case unreachable
    /// Die Liste; `staleSince` ist gesetzt, wenn sie aus dem Cache kommt.
    case value([HabitStatus], staleSince: Date?)
}

/// Die Darstellung, klein und mittel.
///
/// Wie bei den Kalorien kommt `family` als Parameter, damit der
/// Vorschau-Tab der App dieselbe Ansicht zeigen kann.
struct HabitsWidgetView: View {

    let family: WidgetFamily
    let state: HabitsWidgetState

    var body: some View {
        switch state {
        case .noAccess:
            hint(symbol: "lock", text: "Kein Zugang")
        case .unreachable:
            hint(symbol: "wifi.slash", text: "Nicht erreichbar")
        case .value(let habits, let staleSince):
            content(habits, staleSince: staleSince)
        }
    }

    private var rows: Int { family == .systemMedium ? 4 : 3 }

    private func content(_ habits: [HabitStatus], staleSince: Date?) -> some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 6 : 4) {
            // Die Zeilen ueber die Hoehe verteilen statt oben zu stapeln -
            // drei Zeilen und ein leeres unteres Drittel saehen aus, als
            // fehlte etwas.
            ForEach(Array(habits.prefix(rows).enumerated()), id: \.element.id) { index, habit in
                if index > 0 { Spacer(minLength: 0) }
                row(habit)
            }
            if habits.isEmpty {
                Text("Keine Habits").font(.caption).foregroundStyle(.secondary)
            }
            if let staleSince {
                Spacer(minLength: 0)
                Text("Stand \(Self.stamp.string(from: staleSince))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(staleSince == nil ? 1 : 0.6)
    }

    /// Flamme, Zahl, Name - und rechts, was heute zaehlt.
    private func row(_ habit: HabitStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: habit.streak > 0 ? "flame.fill" : "flame")
                .font(family == .systemMedium ? .body : .caption)
                .foregroundStyle(flameColor(habit))
            Text("\(habit.streak)")
                .font((family == .systemMedium ? Font.body : .caption).weight(.semibold).monospacedDigit())
                .frame(minWidth: 18, alignment: .trailing)
            Text(habit.name)
                .font(family == .systemMedium ? .subheadline : .caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            // Der rechte Rand darf nie umbrechen - eher verliert der Name
            // Buchstaben als dass "31/70k" zweizeilig wird.
            trailing(habit)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func trailing(_ habit: HabitStatus) -> some View {
        if habit.unavailable != nil {
            Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.secondary)
        } else if habit.kind == .steps, let progress = habit.progress {
            Text(progress.stepsText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(habit.doneToday ? Color.green : Color.primary)
        } else {
            Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                .font(family == .systemMedium ? .body : .caption)
                .foregroundStyle(habit.doneToday ? Color.green : Color.secondary)
        }
    }

    private func flameColor(_ habit: HabitStatus) -> Color {
        guard habit.streak > 0 else { return .secondary }
        return habit.atRisk ? .orange.opacity(0.45) : .orange
    }

    private func hint(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM., HH:mm"
        return formatter
    }()
}
