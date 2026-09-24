import SwiftUI

/// Rueckwirkend abhaken: die letzten 14 Tage eines Habits, je Tag ein
/// Schalter. Bei „Aufbauen" ist ein Eintrag der Haken, bei „Lassen" der
/// Rueckfall - so, wie der Dienst es zaehlt. Tage vor dem Anlegen fehlen,
/// der Dienst naehme sie ohnehin nicht an.
struct HabitHistorySheet: View {

    let store: HabitsStore
    let habitID: String

    @Environment(\.dismiss) private var dismiss

    private var habit: HabitStatus? {
        store.habits.first { $0.id == habitID }
    }

    private var days: [CalendarDate] {
        let today = CalendarDate.today()
        return (0..<14).map { today.adding(days: -$0) }
            .filter { day in habit?.createdAt.map { day >= $0 } ?? true }
    }

    var body: some View {
        NavigationStack {
            List {
                if let habit {
                    ForEach(days, id: \.self) { day in
                        Button {
                            Task { await store.setMarked(habit, day: day, marked: !habit.isMarked(day)) }
                        } label: {
                            HStack {
                                Text(title(day))
                                Spacer()
                                if habit.kind == .quit {
                                    Image(systemName: habit.isMarked(day) ? "xmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(habit.isMarked(day) ? Color.red : Color.secondary)
                                } else {
                                    Image(systemName: habit.isMarked(day) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(habit.isMarked(day) ? Color.green : Color.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("day-\(day.iso)")
                    }
                }
            }
            .navigationTitle(habit?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func title(_ day: CalendarDate) -> String {
        let today = CalendarDate.today()
        if day == today { return "Heute" }
        if day == today.adding(days: -1) { return "Gestern" }
        return Self.formatter.string(from: day.startOfDay())
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter
    }()
}
