import SwiftUI

/// Die Baeume eines Tages, je mit Uhrzeit, Dauer und Kategorie. Antippen
/// aendert die Kategorie - fuer den Baum, bei dem sie vor dem Pflanzen
/// vergessen war (Felix, 2026-10-05).
struct ForestDaySheet: View {

    let store: ForestStore
    let day: CalendarDate
    @Environment(\.dismiss) private var dismiss
    @State private var choosing: FocusSession?

    var body: some View {
        NavigationStack {
            List(trees) { tree in
                // Ein Baum, der noch im Postausgang wartet, geht mit seiner
                // Kategorie raus - aendern erst, wenn der Dienst ihn kennt.
                if store.canChangeCategory(tree) {
                    Button { choosing = tree } label: { ForestTreeRow(tree: tree, changeable: true) }
                        .accessibilityIdentifier("forestTree")
                } else {
                    ForestTreeRow(tree: tree, changeable: false)
                }
            }
            .navigationTitle(ForestDayRow.title(for: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $choosing) { tree in
                ForestCategorySheet(store: store, purpose: .tree(tree))
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Live aus dem Store, damit eine geaenderte Kategorie sofort hier steht;
    /// der aelteste Baum zuerst, wie auf der Insel.
    private var trees: [FocusSession] {
        store.allSessions.filter { $0.day == day }.sorted { $0.start < $1.start }
    }
}

/// Ein Baum: von wann bis wann, wofuer, wie lange. Farben ausdruecklich als
/// `Color`: in einem Knopf faerbte das hierarchische `.secondary` sonst blau.
private struct ForestTreeRow: View {

    let tree: FocusSession
    let changeable: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Self.clock.string(from: tree.start))–\(Self.clock.string(from: tree.end))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
                Label(tree.categoryName ?? ForestCategorySheet.none, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Text(FocusMinutes.hours(tree.minutes) + " h")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.secondary)
            if changeable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
