import SwiftUI

/// Der Einladungsdialog (Entwurf S. 16): wer einlaedt, wer schon dabei ist,
/// Typ, Regeln, freie Plaetze, der Hinweis zur Sichtbarkeit (Vertrag §5.1),
/// „Ablehnen" | „Mitmachen". Fuer offene Einladungen und Einladungslinks.
struct InvitationDialog: View {
    let target: InvitationTarget

    @State private var invitation: InvitationView?
    @State private var preview: InviteLinkPreview?
    @State private var errorMessage: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    private var api: CohabitAPI { Session.shared.api() }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            Group {
                if let from = invitation?.from ?? preview?.from {
                    if let cohabit = invitation?.cohabit ?? preview?.cohabit {
                        InvitationCardContent(from: from, cohabit: cohabit, full: preview?.full ?? false,
                                              busy: busy, errorMessage: errorMessage,
                                              decline: { Task { await decline() } },
                                              accept: { Task { await accept() } })
                    } else {
                        friendCard(from)
                    }
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ink.ink)
                            .multilineTextAlignment(.center)
                        Button("Schließen") { dismiss() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                } else {
                    ProgressView()
                        .padding(30)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 22)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            switch target {
            case .pending(let found):
                invitation = found
            case .pendingId(let id):
                let list: [InvitationView] = try await api.get("/me/invitations")
                guard let found = list.first(where: { $0.id == id }) else {
                    errorMessage = "Die Einladung ist nicht mehr offen."
                    return
                }
                invitation = found
            case .join(let code):
                preview = try await api.get("/invite-links/\(code)")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accept() async {
        busy = true
        defer { busy = false }
        do {
            var cohabitId: String?
            switch target {
            case .pending(let found):
                let detail: CohabitDetail = try await api.send("POST", "/invitations/\(found.id)/accept", body: CohabitAPI.EmptyBody())
                cohabitId = detail.id
            case .pendingId(let id):
                let detail: CohabitDetail = try await api.send("POST", "/invitations/\(id)/accept", body: CohabitAPI.EmptyBody())
                cohabitId = detail.id
            case .join(let code):
                let result: AcceptResult = try await api.send("POST", "/invite-links/\(code)/accept", body: CohabitAPI.EmptyBody())
                cohabitId = result.cohabitId
                Session.shared.store(result.me)
            }
            DataBus.shared.changed()
            await Session.shared.refreshMe()
            dismiss()
            if let cohabitId {
                Router.shared.showCohabit(cohabitId, section: .overview)
            } else {
                Toast.shared.show("Angenommen")
            }
            Task { await WidgetSync.refresh() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decline() async {
        if case .join = target {
            dismiss()
            return
        }
        let id: String
        switch target {
        case .pending(let found): id = found.id
        case .pendingId(let pendingId): id = pendingId
        case .join: return
        }
        busy = true
        defer { busy = false }
        do {
            try await api.sendIgnoringResponse("POST", "/invitations/\(id)/decline", body: CohabitAPI.EmptyBody())
            DataBus.shared.changed()
            await Session.shared.refreshMe()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ein Freundes-Link: nur annehmen oder nicht.
    private func friendCard(_ from: PersonView) -> some View {
        VStack(spacing: 18) {
            AvatarView(person: from, size: 64, ring: nil)
            Text("\(from.displayName) möchte mit dir befreundet sein")
                .font(.heading(24))
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.center)
            if let errorMessage { ErrorLine(message: errorMessage) }
            HStack(spacing: 12) {
                Button("Ablehnen") { dismiss() }
                    .buttonStyle(OutlineButtonStyle(height: 52))
                Button("Annehmen") { Task { await accept() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            }
        }
        .padding(24)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// Der Inhalt der Einladungskarte - auch beim Start ohne Zugang, dort mit den
/// Feldern fuer die Anmeldung darunter.
struct InvitationCardContent<Extra: View>: View {
    let from: PersonView
    let cohabit: InvitationCohabit
    var full = false
    var busy = false
    var errorMessage: String?
    var acceptTitle = "Mitmachen"
    var canAccept = true
    let decline: () -> Void
    let accept: () -> Void
    @ViewBuilder var extra: Extra

    private var colors: PaletteColor { cohabit.ref.typeColor.colors }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(spacing: -10) {
                    ForEach(Array(([from] + cohabit.members.filter { $0.id != from.id }).prefix(3))) { person in
                        AvatarView(person: person, size: 52)
                    }
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: 0x5B3FD9), in: Circle())
                        .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 3))
                }
                Text("\(from.shortLabel(me: nil)) lädt dich zu „\(cohabit.ref.name)“ ein")
                    .font(.heading(26))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    colors.surface
                    CornerCircle(color: colors.accent.opacity(0.6), corner: .topTrailing, size: 130)
                }
            }

            VStack(spacing: 14) {
                FlowLayout(spacing: 8) {
                    Chip(text: cohabit.typeLine)
                    ForEach(cohabit.rules.filter { $0 != cohabit.typeLine }, id: \.self) { Chip(text: $0) }
                    Chip(text: "\(cohabit.seats.free) von \(cohabit.seats.max) Plätzen frei")
                }
                .frame(maxWidth: .infinity)
                Text(full ? "Alle Plätze sind belegt."
                     : "Deine Check-ins und Beweisfotos sind für alle Mitglieder sichtbar.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                extra
                if let errorMessage { ErrorLine(message: errorMessage) }
                HStack(spacing: 12) {
                    Button("Ablehnen", action: decline)
                        .buttonStyle(OutlineButtonStyle(height: 52))
                        .accessibilityIdentifier("inviteDecline")
                    Button(action: accept) {
                        if busy { ProgressView().tint(Ink.onInk) } else { Text(acceptTitle) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || full || !canAccept)
                    .accessibilityIdentifier("inviteAccept")
                }
            }
            .padding(20)
            .background(Ink.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        // .contain: sonst ueberschriebe die Kennung die der Knoepfe darin.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invitationDialog")
    }
}

extension InvitationCardContent where Extra == EmptyView {
    init(from: PersonView, cohabit: InvitationCohabit, full: Bool = false, busy: Bool = false,
         errorMessage: String? = nil, decline: @escaping () -> Void, accept: @escaping () -> Void) {
        self.init(from: from, cohabit: cohabit, full: full, busy: busy, errorMessage: errorMessage,
                  decline: decline, accept: accept, extra: { EmptyView() })
    }
}
