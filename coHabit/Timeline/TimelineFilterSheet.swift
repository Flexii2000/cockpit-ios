import SwiftUI

/// Der Filter der Timeline als Abhak-Liste: oben „Alle", darunter jedes aktive
/// Co-Habit mit Farbpunkt, Name und Haken. Mehrfachauswahl, jede Aenderung
/// wirkt sofort - die Timeline dahinter laedt schon neu.
struct TimelineFilterSheet: View {

    let store: TimelineStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Habits") { dismiss() }
                FormCard {
                    FilterRow(title: "Alle", color: nil, isOn: store.filter.allVisible(store.cohabits),
                              identifier: "filterAll") {
                        Task { await store.toggleAll() }
                    }
                    ForEach(store.cohabits) { ref in
                        FormDivider()
                        FilterRow(title: ref.name, color: ref.color, isOn: store.filter.isVisible(ref.id),
                                  identifier: "filterRow-\(ref.id)") {
                            Task { await store.toggle(ref.id) }
                        }
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Eine Zeile: Farbpunkt, Name, Haken.
private struct FilterRow: View {
    let title: String
    /// `nil` bei „Alle" - der Platz bleibt, damit die Namen buendig stehen.
    let color: PaletteKey?
    let isOn: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color?.colors.accent ?? .clear)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.accent)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "an" : "aus")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
