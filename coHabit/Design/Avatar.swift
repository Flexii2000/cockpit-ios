import SwiftUI

/// Ein runder Avatar: Foto, sonst die Initialen auf der Personenfarbe.
/// Die angemeldete Person steht als „Du" in Tinte (wie in den Entwuerfen).
struct AvatarView: View {
    let person: PersonView
    var size: CGFloat = 36
    var ring: Color? = Ink.surface

    @Environment(\.meId) private var meId

    var body: some View {
        let isMe = person.id == meId
        ZStack {
            if let photo = person.avatarPhotoId {
                PhotoView(id: photo, size: .thumb, placeholder: person.color.colors.surface)
            } else {
                Circle().fill(isMe ? Ink.ink : person.color.colors.surface)
                Text(isMe ? "Du" : person.initials)
                    .font(.system(size: size * 0.36, weight: .heavy))
                    .foregroundStyle(isMe ? Ink.onInk : person.color.colors.onSurface)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if let ring { Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.06)) }
        }
        .accessibilityLabel(person.label(me: meId))
    }
}

/// Bis zu drei Avatare uebereinander, dahinter „+n". „Du" steht zuletzt und
/// damit obenauf - wie im Entwurf („LK MB Du").
struct AvatarStack: View {
    let people: [PersonView]
    var total: Int? = nil
    var size: CGFloat = 32
    var limit = 3

    @Environment(\.meId) private var meId

    var body: some View {
        let others = people.filter { $0.id != meId }
        let me = people.filter { $0.id == meId }
        let shown = Array(others.prefix(limit - me.count)) + me
        let rest = (total ?? people.count) - shown.count
        HStack(spacing: -size * 0.28) {
            ForEach(shown) { person in
                AvatarView(person: person, size: size)
            }
            if rest > 0 {
                Text("+\(rest)")
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                    .frame(width: size, height: size)
                    .background(Ink.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 2))
            }
        }
    }
}
