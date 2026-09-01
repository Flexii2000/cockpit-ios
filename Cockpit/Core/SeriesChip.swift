import SwiftUI

/// Umschalter fuer eine Diagrammserie. Zugleich die Legende - eine zweite
/// Liste mit denselben Farben waere Wiederholung.
struct SeriesChip: View {

    let title: String
    let color: Color
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title).font(.caption)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isOn ? color.opacity(0.18) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? .primary : .secondary)
    }
}
