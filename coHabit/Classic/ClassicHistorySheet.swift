import SwiftUI

/// Rueckwirkend abhaken: die letzten 14 Tage eines Habits, je Tag ein
/// Schalter. Bei „Aufbauen" ist ein Eintrag der Haken, bei „Lassen" der
/// Rueckfall - so, wie der Dienst es zaehlt. Tage vor dem Start oder Beitritt
/// und vor dem fruehesten Tag, den der Dienst noch annimmt, fehlen.
struct ClassicHistorySheet: View {

    let store: ClassicStore
    let habitID: String

    @Environment(\.dismiss) private var dismiss

    private var habit: ClassicHabit? {
        store.habits.first { $0.id == habitID }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = store.errorMessage {
                    ErrorLine(message: message)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let habit {
                    let today = habit.today
                    ForEach(habit.backfillDays(today: today), id: \.self) { day in
                        Button {
                            Task { await store.setMarked(habit, day: day, marked: !habit.isMarked(day)) }
                        } label: {
                            HStack {
                                Text(title(day, today: today))
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
        .tint(nil as Color?)
    }

    private func title(_ day: CalendarDate, today: CalendarDate) -> String {
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
