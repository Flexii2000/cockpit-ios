import SwiftUI

/// Das Profil (Entwurf S. 5, Vertrag §5.2.5).
struct ProfileView: View {

    @State private var healthAsked = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var showsDeleteInput = false
    /// Je Geraet, wie die Wahl Dashboard/Liste auf „Heute".
    @AppStorage(ClassicList.storageKey) private var classicList = false
    @Environment(\.openURL) private var openURL

    private var session: Session { Session.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let me = session.me {
                    header(me)
                    HStack(spacing: 10) {
                        countTile(me.counts.cohabits, "Co-Habits", .peach)
                        countTile(me.counts.friends, "Freunde", .mint)
                        countTile(me.counts.wins, "Siege", .butter)
                    }
                    FormCard {
                        NavigationLink(value: Route.notifications) { FormRow(title: "Benachrichtigungen") }
                        FormDivider()
                        NavigationLink(value: Route.health) {
                            FormRow(title: "Health-Verbindung") {
                                if healthAsked { Chip(text: "verbunden", fill: PaletteKey.mint.colors.surface, weight: .bold, size: 12) }
                            }
                        }
                        FormDivider()
                        NavigationLink(value: Route.friends) {
                            FormRow(title: "Freunde & Einladungen") {
                                let new = me.pendingInvitations + me.incomingFriendRequests
                                if new > 0 {
                                    Chip(text: "\(new) neu", fill: Ink.accent, foreground: .white, weight: .bold, size: 12)
                                }
                            }
                        }
                        .accessibilityIdentifier("profileFriends")
                        FormDivider()
                        NavigationLink(value: Route.archived) { FormRow(title: "Archivierte Co-Habits") }
                        FormDivider()
                        NavigationLink(value: Route.export) { FormRow(title: "Daten exportieren") }
                        FormDivider()
                        NavigationLink(value: Route.appLinks) { FormRow(title: "App verbinden") }
                        FormDivider()
                        Button {
                            openURL(Self.legalURL)
                        } label: {
                            FormRow(title: "Rechtliches")
                        }
                    }
                    .buttonStyle(.plain)
                    FormCard {
                        ToggleRow(title: "Klassische Liste", isOn: $classicList, identifier: "classicList")
                    }
                    FormCard {
                        Button { confirmSignOut = true } label: {
                            FormRow(title: "Abmelden", chevron: false)
                        }
                        .accessibilityIdentifier("signOut")
                        FormDivider()
                        Button { confirmDelete = true } label: {
                            FormRow(title: "Account löschen", titleColor: Ink.danger, chevron: false)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView().padding(.vertical, 60)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .statusBarScrim()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .refreshable { await session.refreshMe() }
        .task {
            await session.refreshMe()
            healthAsked = await CohabitHealthSync.shared.hasAsked()
        }
        .onChange(of: DataBus.shared.revision) { Task { await session.refreshMe() } }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await session.signOut() } }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Account löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Weiter", role: .destructive) { showsDeleteInput = true }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Profil, Einträge, Nachrichten und Fotos werden gelöscht.")
        }
        .sheet(isPresented: $showsDeleteInput) {
            DeleteAccountSheet()
        }
    }

    static var legalURL: URL {
        Backend.cohabit.url.deletingLastPathComponent().appending(path: "rechtliches")
    }

    private func header(_ me: MeView) -> some View {
        VStack(spacing: 8) {
            AvatarView(person: me.person, size: 96, ring: nil)
            Text(me.person.displayName)
                .font(.heading(26))
                .foregroundStyle(Ink.ink)
                .padding(.top, 6)
            Text("@\(me.person.username)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.muted)
            NavigationLink(value: Route.editProfile) {
                Text("Profil bearbeiten")
            }
            .buttonStyle(SmallOutlineButtonStyle())
            .padding(.top, 6)
            .accessibilityIdentifier("editProfile")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background {
            ZStack {
                Ink.surface
                CornerCircle(color: PaletteKey.peach.colors.surface, corner: .topLeading, size: 130, inset: 0.3)
                CornerCircle(color: PaletteKey.periwinkle.colors.surface, corner: .topTrailing, size: 110, inset: 0.45)
                    .offset(y: 40)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }

    private func countTile(_ value: Int, _ label: String, _ color: PaletteKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.figure(28))
                .foregroundStyle(Ink.ink)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(color.colors.surface, padding: 14)
    }
}

/// Zweite Stufe der Loeschung: „LÖSCHEN" eintippen (Vertrag §5.2.5).
struct DeleteAccountSheet: View {
    @State private var input = ""
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Account löschen") { dismiss() }
            Text("Zum Bestätigen LÖSCHEN eingeben.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.muted)
            InputField(placeholder: "LÖSCHEN", text: $input, identifier: "deleteConfirm", capitalization: .characters)
            Spacer()
            Button {
                deleting = true
                Task {
                    do {
                        try await Session.shared.api().sendIgnoringResponse("DELETE", "/me",
                                                                            body: DeleteMeRequest(confirm: input))
                        dismiss()
                        await Session.shared.wipe(reason: nil)
                    } catch {
                        Toast.shared.show(error)
                    }
                    deleting = false
                }
            } label: {
                if deleting { ProgressView().tint(.white) } else { Text("Endgültig löschen") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: Ink.danger, foreground: .white))
            .disabled(input != "LÖSCHEN" || deleting)
        }
        .padding(Metrics.gutter)
        .screenBackground()
        .presentationDetents([.medium])
    }
}

struct DeleteMeRequest: Encodable {
    let confirm: String
}
