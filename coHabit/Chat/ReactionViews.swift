import SwiftUI
import UIKit

// Emoji-Reaktionen (Vertrag §2.7a) - im Chat und in der Timeline gleich:
// langer Druck oeffnet die Leiste samt Aktionen, die Pille sitzt an der
// Unterkante, ein Tipp darauf zeigt, wer wie reagiert hat.

/// Bis zu drei Emojis, die haeufigsten zuerst, ab zwei Reaktionen die
/// Gesamtzahl. Ist die eigene dabei, ist die Pille in der Akzentfarbe umrandet.
struct ReactionPill: View {
    let reactions: [ReactionView]
    let open: () -> Void

    static let height: CGFloat = 28
    /// So viel davon liegt auf der Blase - weniger als ihr Innenabstand.
    static let overlap: CGFloat = 7

    var body: some View {
        let total = Reactions.total(reactions)
        let mine = reactions.contains(where: \.mine)
        Button(action: open) {
            HStack(spacing: 1) {
                ForEach(Reactions.top(reactions), id: \.self) { emoji in
                    Text(emoji)
                }
                if total >= 2 {
                    Text("\(total)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Ink.ink)
                        .padding(.leading, 4)
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background(Ink.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(mine ? Ink.accent : Ink.track, lineWidth: mine ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reactions.map { "\($0.reaction) \($0.count)" }.joined(separator: ", "))
        .accessibilityHint("Reaktionen")
        .accessibilityIdentifier("reactionPill")
    }
}

extension View {
    /// Die Pille an der Unterkante (wie in WhatsApp): ein Stueck auf der Blase,
    /// der Rest darunter - nur so weit darauf, wie die Blase Rand hat, damit
    /// sie bei einer Zeile Text nichts verdeckt. Auf der Seite, auf der die
    /// Nachricht steht; darunter bleibt Platz, damit die naechste Zeile frei ist.
    func reactionPill(_ reactions: [ReactionView], trailing: Bool, open: @escaping () -> Void) -> some View {
        overlay(alignment: trailing ? .bottomTrailing : .bottomLeading) {
            if !reactions.isEmpty {
                // Verschoben statt ueber eine Ausrichtungslinie: die kommt
                // durch `if` und `padding` nicht zuverlaessig an.
                ReactionPill(reactions: reactions, open: open)
                    .padding(.horizontal, 10)
                    .offset(y: ReactionPill.height - ReactionPill.overlap)
            }
        }
        .padding(.bottom, reactions.isEmpty ? 0 : ReactionPill.height - ReactionPill.overlap + 2)
    }
}

/// Was der lange Druck ausser Reagieren anbietet (Löschen, Melden, Blockieren
/// im Chat; Antworten in der Timeline).
struct ReactionMenuAction: Identifiable {
    let title: String
    let systemImage: String
    var destructive = false
    let identifier: String
    let run: @MainActor () -> Void

    var id: String { identifier }
}

/// Das Blatt hinter dem langen Druck: oben die Leiste mit der Schnellauswahl
/// und „+", darunter die Aktionen.
///
/// Ein eigenes Blatt statt des Kontextmenues: dort laesst sich keine Leiste
/// mit eigenen Knoepfen unterbringen, und eine Palette im Menue scrollt bei
/// sieben Eintraegen seitlich (siehe docs/ENTSCHEIDUNGEN.md).
struct ReactionActionsSheet: View {
    /// Das eigene Emoji - in der Leiste hervorgehoben.
    let current: String?
    var canReact = true
    let actions: [ReactionMenuAction]
    let react: (String) -> Void
    /// Fuer die Aktionen: laeuft erst, wenn das Blatt zu ist (ein Dialog
    /// danach kaeme sonst nicht hoch).
    let afterDismiss: (@escaping @MainActor () -> Void) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            if canReact {
                EmojiBar(current: current) { emoji in
                    react(emoji)
                    dismiss()
                }
            }
            if !actions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { FormDivider() }
                        Button {
                            afterDismiss(action.run)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 24)
                                Text(action.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(action.destructive ? Ink.danger : Ink.ink)
                            .frame(height: Self.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.identifier)
                    }
                }
                .padding(.horizontal, 16)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .screenBackground()
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }

    private static let rowHeight: CGFloat = 54

    private var height: CGFloat {
        var height: CGFloat = 26 + 16
        if canReact { height += EmojiBar.height }
        if !actions.isEmpty {
            if canReact { height += 14 }
            height += CGFloat(actions.count) * Self.rowHeight + CGFloat(actions.count - 1)
        }
        return height
    }
}

/// 💪 🔥 🙌 ❤️ 😂 👏 und „+" - in einer Zeile, ohne seitliches Scrollen: die
/// Felder teilen sich die Breite. Ist das eigene Emoji keins der sechs, steht
/// es als achtes davor, hervorgehoben.
struct EmojiBar: View {
    let current: String?
    let pick: (String) -> Void

    static let height: CGFloat = 58

    private var emojis: [String] {
        guard let current, !Emoji.quickPicks.contains(current) else { return Emoji.quickPicks }
        return Emoji.quickPicks + [current]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(emojis, id: \.self) { emoji in
                let selected = emoji == current
                Button {
                    pick(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 42, height: 42)
                        .background(selected ? Ink.accentSoft : Color.clear, in: Circle())
                        .overlay(Circle().strokeBorder(selected ? Ink.accent : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("react-\(emoji)")
            }
            OtherEmojiField(pick: pick)
                .frame(width: 42, height: 42)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(Ink.surface, in: Capsule())
    }
}

/// „+": ein Feld, das beim Antippen die Emoji-Tastatur oeffnet (mit ihrer
/// Suche) und das erste Emoji, das darin landet, abgibt. iOS hat keine
/// oeffentliche Emoji-Auswahl; ist die Emoji-Tastatur nicht eingerichtet,
/// kommt die normale - dort ist sie ueber den Globus erreichbar, und alles
/// andere als ein Emoji wird verworfen.
struct OtherEmojiField: UIViewRepresentable {
    let pick: (String) -> Void

    func makeUIView(context: Context) -> EmojiInputField {
        let field = EmojiInputField()
        field.textAlignment = .center
        field.tintColor = .clear
        field.font = .systemFont(ofSize: 26)
        field.attributedPlaceholder = NSAttributedString(string: "+", attributes: [
            .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: UIColor(Ink.muted),
        ])
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.layer.cornerRadius = 21
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.accessibilityLabel = "Anderes Emoji"
        field.accessibilityIdentifier = "reactOther"
        return field
    }

    func updateUIView(_ field: EmojiInputField, context: Context) {
        context.coordinator.pick = pick
    }

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var pick: (String) -> Void

        init(pick: @escaping (String) -> Void) {
            self.pick = pick
        }

        @objc func changed(_ field: UITextField) {
            let text = field.text ?? ""
            field.text = ""
            guard let emoji = Emoji.first(in: text) else { return }
            field.resignFirstResponder()
            pick(emoji)
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            field.backgroundColor = UIColor(Ink.accentSoft)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            field.backgroundColor = .clear
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}

/// Ein Textfeld, das die Emoji-Tastatur verlangt, wenn sie eingerichtet ist.
final class EmojiInputField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    /// Ohne eigene Kennung merkt sich iOS die zuletzt benutzte Tastatur je
    /// App - und nimmt die statt der verlangten.
    override var textInputContextIdentifier: String? { "cohabit.emoji" }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    /// Kein Einsetzen-Menue im „+".
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}

/// Das Blatt „Reaktionen": wer wie reagiert hat - Avatar, Name, Emoji; die
/// eigene Zeile mit „Entfernen".
struct ReactionsListSheet: View {
    let reactions: [ReactionView]
    let remove: () -> Void

    @Environment(\.meId) private var meId
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable, Hashable {
        let id: String
        let person: PersonView?
        let emoji: String
        /// Nur ohne `people` (aelterer Dienst): wie viele.
        let count: Int
        let mine: Bool
    }

    /// Je Person eine Zeile, in der Reihenfolge des Dienstes. Kennt der Dienst
    /// `people` nicht, eine Zeile je Emoji mit der Anzahl.
    nonisolated static func rows(_ reactions: [ReactionView], meId: String?) -> [Row] {
        reactions.flatMap { reaction -> [Row] in
            if reaction.people.isEmpty {
                return [Row(id: "emoji-\(reaction.reaction)", person: nil, emoji: reaction.reaction,
                            count: reaction.count, mine: reaction.mine)]
            }
            return reaction.people.map { person in
                Row(id: "\(person.id)-\(reaction.reaction)", person: person, emoji: reaction.reaction,
                    count: 1, mine: person.id == meId)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Reaktionen") { dismiss() }
                FormCard {
                    ForEach(Array(Self.rows(reactions, meId: meId).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { FormDivider() }
                        rowView(row)
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            if let person = row.person {
                AvatarView(person: person, size: 40, ring: nil)
                Text(row.mine ? "Du" : person.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
            } else {
                Text("\(row.count)")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Ink.ink)
            }
            Spacer(minLength: 8)
            if row.mine {
                Button("Entfernen") {
                    remove()
                    dismiss()
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Ink.accent)
                .accessibilityIdentifier("reactionRemove")
            }
            Text(row.emoji)
                .font(.system(size: 26))
        }
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reactionRow-\(row.id)")
    }
}
