import SwiftUI
import UIKit

// Die Blaetter hinter dem Menue der Detailseite: Mitglieder, Pausen,
// Einladen, Benachrichtigungen, eigene Eintraege.

// MARK: - Mitglieder

struct MembersSheet: View {
    let store: CohabitDetailStore

    @State private var nudgeTarget: PersonView?
    @State private var nudgeText = ""
    @State private var removeTarget: PersonView?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meId) private var meId

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Mitglieder",
                            subtitle: store.detail.map { "\($0.seats.used) von \($0.seats.max) Plätzen" }) { dismiss() }
                if let detail = store.detail {
                    FormCard {
                        ForEach(Array(detail.members.enumerated()), id: \.element.id) { index, member in
                            if index > 0 { FormDivider() }
                            row(member, detail: detail)
                        }
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDragIndicator(.visible)
        .alert("\(nudgeTarget?.displayName ?? "") anstupsen", isPresented: Binding(
            get: { nudgeTarget != nil }, set: { if !$0 { nudgeTarget = nil } })) {
            TextField("Heute noch „\(store.detail?.ref.name ?? "")“?", text: $nudgeText)
            Button("Stupsen") {
                if let target = nudgeTarget {
                    let text = nudgeText.trimmingCharacters(in: .whitespaces)
                    Task { await store.nudge(target, text: text.isEmpty ? nil : String(text.prefix(60))) }
                }
                nudgeText = ""
            }
            Button("Abbrechen", role: .cancel) { nudgeText = "" }
        }
        .confirmationDialog("\(removeTarget?.displayName ?? "") entfernen?", isPresented: Binding(
            get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let target = removeTarget { Task { await store.remove(member: target) } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    /// `ACTIVE`, `INVITED` (Einladung offen), `PAUSED` (Pause laeuft) - was der
    /// Dienst sonst noch schickt, bleibt ohne Zusatz.
    nonisolated static func stateText(_ state: String) -> String {
        switch state {
        case "INVITED": " · eingeladen"
        case "PAUSED": " · pausiert"
        default: ""
        }
    }

    private func row(_ member: Member, detail: CohabitDetail) -> some View {
        let isMe = member.person.id == meId
        let openToday = (detail.ref.type == .streak || detail.ref.type == .challenge)
            && !detail.summary.doneTodayBy.contains(member.person.id)
            && member.state == "ACTIVE"
        return HStack(spacing: 12) {
            AvatarView(person: member.person, size: 40, ring: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.person.label(me: meId))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                Text("@\(member.person.username)" + (member.role == .admin ? " · Admin" : "")
                     + Self.stateText(member.state))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            Spacer()
            if !isMe && openToday && !detail.summary.archived {
                Button("Stupsen") { nudgeTarget = member.person }
                    .buttonStyle(SmallOutlineButtonStyle())
                    .accessibilityIdentifier("nudge-\(member.person.id)")
            }
            if detail.isAdmin && !isMe {
                Menu {
                    if member.state == "ACTIVE" {
                        Button("Zum Admin machen", systemImage: "crown") {
                            Task { await store.makeAdmin(member.person) }
                        }
                    }
                    Button(member.state == "INVITED" ? "Einladung zurückziehen" : "Entfernen",
                           systemImage: "person.fill.xmark", role: .destructive) {
                        removeTarget = member.person
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Mehr zu \(member.person.displayName)")
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Pausen

struct PausesSheet: View {
    let store: CohabitDetailStore

    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(6 * 86_400)
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Pausen") { dismiss() }
                if let detail = store.detail, !detail.myPauses.isEmpty {
                    FormCard {
                        ForEach(Array(detail.myPauses.enumerated()), id: \.element.id) { index, pause in
                            if index > 0 { FormDivider() }
                            HStack {
                                Text("\(Formats.date(pause.from)) – \(Formats.date(pause.to))")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await store.removePause(pause) }
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(Ink.danger)
                                }
                                .accessibilityLabel("Pause löschen")
                            }
                            .frame(minHeight: 52)
                        }
                    }
                }
                FormCard {
                    DatePicker("Von", selection: $from, displayedComponents: .date)
                        .font(.system(size: 17, weight: .bold))
                        .frame(minHeight: 56)
                    FormDivider()
                    DatePicker("Bis", selection: $to, in: from..., displayedComponents: .date)
                        .font(.system(size: 17, weight: .bold))
                        .frame(minHeight: 56)
                }
                .environment(\.locale, Locale(identifier: "de_DE"))
                Button {
                    saving = true
                    Task {
                        let zone = TimeZone(identifier: store.detail?.config.timezone ?? "") ?? .current
                        _ = await store.addPause(from: CalendarDate(date: from, in: zone),
                                                 to: CalendarDate(date: to, in: zone))
                        saving = false
                    }
                } label: {
                    Text("Pause eintragen")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving)
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Einladen

struct InviteSheet: View {
    let cohabitId: String
    let name: String

    @State private var candidates: InviteCandidates?
    @State private var errorMessage: String?
    @State private var sharing: ShareItem?
    @State private var linkBusy = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meId) private var meId

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Einladen",
                            subtitle: candidates.map { "\($0.seats.used) von \($0.seats.max)" }) { dismiss() }
                InviteLinkCard(busy: linkBusy) { Task { await shareLink() } }
                if let errorMessage { ErrorLine(message: errorMessage) }
                if let candidates {
                    if candidates.people.isEmpty {
                        Text("Noch keine Freunde")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        FormCard {
                            ForEach(Array(candidates.people.enumerated()), id: \.element.id) { index, candidate in
                                if index > 0 { FormDivider() }
                                PersonInviteRow(person: candidate.person,
                                                state: candidate.isMember ? .member : (candidate.isInvited ? .invited : .invite),
                                                enabled: candidates.canInvite && candidates.seats.free > 0) {
                                    Task { await invite(candidate.person) }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDragIndicator(.visible)
        .task { await load() }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private var api: CohabitAPI { Session.shared.api() }

    private func load() async {
        do {
            candidates = try await api.get("/cohabits/\(cohabitId)/invite-candidates")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func invite(_ person: PersonView) async {
        do {
            candidates = try await api.send("POST", "/cohabits/\(cohabitId)/invitations",
                                            body: InviteRequest(personIds: [person.id]))
            DataBus.shared.changed()
        } catch {
            Toast.shared.show(error)
        }
    }

    private func shareLink() async {
        linkBusy = true
        defer { linkBusy = false }
        do {
            let link: LinkInfo = try await api.send("POST", "/cohabits/\(cohabitId)/invite-link", body: CohabitAPI.EmptyBody())
            if let url = URL(string: link.url) { sharing = ShareItem(url: url) }
        } catch {
            Toast.shared.show(error)
        }
    }
}

struct InviteRequest: Encodable {
    let personIds: [String]
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Die violette Karte „Einladungslink · Teilen".
struct InviteLinkCard: View {
    var busy = false
    let share: () -> Void

    var body: some View {
        HStack {
            Text("Einladungslink")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            Button(action: share) {
                Group {
                    if busy { ProgressView().tint(Color(hex: 0x1C1B2E)) } else { Text("Teilen") }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1B2E))
                .frame(width: 86, height: 46)
                .background(.white, in: Capsule())
            }
            .disabled(busy)
            .accessibilityIdentifier("shareInviteLink")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            ZStack {
                Color(hex: 0x5B3FD9)
                CornerCircle(color: .white.opacity(0.12), corner: .bottomTrailing, size: 110)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// Eine Person mit „Einladen" / „Eingeladen" / „Dabei".
struct PersonInviteRow: View {
    enum State { case invite, invited, member }

    let person: PersonView
    let state: State
    var enabled = true
    let invite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(person: person, size: 42, ring: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                Text("@\(person.username)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            Spacer()
            switch state {
            case .invite:
                Button("Einladen", action: invite)
                    .buttonStyle(SmallOutlineButtonStyle())
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                    .accessibilityIdentifier("invite-\(person.id)")
            case .invited:
                Text("Eingeladen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.muted)
            case .member:
                Text("Dabei")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.muted)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Der Teilen-Dialog des Systems.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Benachrichtigungen und Freigaben je Co-Habit

struct CohabitSettingsSheet: View {
    let store: CohabitDetailStore

    @State private var settings: MySettings?
    @Environment(\.dismiss) private var dismiss

    enum Choice: Hashable { case global, on, off }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Benachrichtigungen") { dismiss() }
                if let binding = Binding($settings), let detail = store.detail {
                    FormCard {
                        ToggleRow(title: "Stumm", isOn: binding.muted)
                        FormDivider()
                        choiceRow("Check-ins", value: binding.checkins)
                        FormDivider()
                        choiceRow("Chat", value: binding.chat)
                    }
                    .disabled(false)
                    if detail.ref.type == .abstinence || detail.config.health != nil {
                        FormCard {
                            if detail.ref.type == .abstinence {
                                ToggleRow(title: "Unterbrechungen teilen", isOn: binding.shareBreaks)
                            }
                            if detail.ref.type == .abstinence && detail.config.health != nil { FormDivider() }
                            if detail.config.health != nil {
                                ToggleRow(title: "Health-Werte teilen", isOn: binding.healthConsent)
                                    // kcal aus Healthy: nur mit Healthy-Zugang.
                                    .disabled(detail.health?.isFromHealthy == true && !HealthyAccess.isAvailable)
                            }
                        }
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDragIndicator(.visible)
        .onAppear { settings = store.detail?.mySettings }
        .onChange(of: settings) { old, new in
            guard let old, let new, old != new else { return }
            if new.healthConsent && !old.healthConsent && store.detail?.health?.isFromHealthy != true {
                Task { await store.enableHealth() }
            } else {
                Task { await store.save(settings: new) }
            }
        }
    }

    private func choiceRow(_ title: String, value: Binding<Bool?>) -> some View {
        let choice = Binding<Choice>(
            get: { value.wrappedValue.map { $0 ? .on : .off } ?? .global },
            set: { value.wrappedValue = $0 == .global ? nil : ($0 == .on) })
        return HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Ink.ink)
            Spacer()
            Picker(title, selection: choice) {
                Text("Wie im Profil").tag(Choice.global)
                Text("An").tag(Choice.on)
                Text("Aus").tag(Choice.off)
            }
            .tint(Ink.muted)
        }
        .frame(minHeight: 56)
        .opacity(settings?.muted == true ? 0.4 : 1)
    }
}

// MARK: - Eigene Eintraege

struct EntriesSheet: View {
    let store: CohabitDetailStore

    @State private var editing: Checkin?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Meine Einträge") { dismiss() }
                if let detail = store.detail {
                    FormCard {
                        ForEach(Array(detail.myCheckins.enumerated()), id: \.element.id) { index, checkin in
                            if index > 0 { FormDivider() }
                            HStack(spacing: 12) {
                                if let photo = checkin.photoId {
                                    PhotoView(id: photo, size: .thumb, placeholder: detail.ref.color.colors.surface)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Formats.dayTitle(checkin.date))
                                        .font(.system(size: 16, weight: .heavy))
                                        .foregroundStyle(Ink.ink)
                                    let details = [checkin.kind == .break ? "Unterbrechung" : nil,
                                                   checkin.valueText, checkin.caption ?? checkin.note]
                                        .compactMap { $0 }.filter { !$0.isEmpty }
                                    if !details.isEmpty {
                                        Text(details.joined(separator: " · "))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Ink.muted)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if checkin.editable {
                                    Menu {
                                        Button("Bearbeiten", systemImage: "pencil") { editing = checkin }
                                        Button("Löschen", systemImage: "trash", role: .destructive) {
                                            Task { await store.delete(checkin) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Ink.ink)
                                            .frame(width: 36, height: 36)
                                    }
                                    .accessibilityLabel("Eintrag bearbeiten")
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .presentationDragIndicator(.visible)
        .sheet(item: $editing) { checkin in
            EditCheckinSheet(store: store, checkin: checkin)
        }
    }
}

struct EditCheckinSheet: View {
    let store: CohabitDetailStore
    let checkin: Checkin

    @State private var value = ""
    @State private var note = ""
    @State private var caption = ""
    @State private var minutes = ""
    @State private var distance = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    /// Ein Lauf: Dauer und Distanz statt eines Werts.
    private var isRun: Bool { checkin.run != nil || store.detail?.summary.isRunEntry == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Eintrag bearbeiten", subtitle: Formats.dayTitle(checkin.date)) { dismiss() }
            if isRun {
                RunInputFields(minutes: $minutes, distance: $distance)
            } else if checkin.value != nil || store.detail?.config.tracking.isValue == true {
                FieldLabel(text: "Wert")
                InputField(placeholder: "Wert", text: $value, keyboard: .decimalPad)
            }
            FieldLabel(text: "Notiz")
            InputField(placeholder: "Notiz", text: $note)
            if checkin.photoId != nil {
                FieldLabel(text: "Caption")
                InputField(placeholder: "Wie war's?", text: $caption)
            }
            Spacer()
            Button("Sichern") {
                saving = true
                Task {
                    let update = CheckinUpdate(value: isRun ? nil : ValueEntrySheet.number(value),
                                               note: note.isEmpty ? nil : note,
                                               caption: caption.isEmpty ? nil : caption,
                                               durationMinutes: isRun ? RunEntrySheet.minutes(minutes) : nil,
                                               distanceKm: isRun ? RunEntrySheet.distance(distance) : nil)
                    if await store.update(checkin, update) { dismiss() }
                    saving = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            // Ein Lauf ohne lesbare Dauer oder Distanz: lieber nicht sichern
            // als still „unveraendert" schicken.
            .disabled(saving || (isRun && (RunEntrySheet.minutes(minutes) == nil
                                           || RunEntrySheet.distance(distance) == nil)))
            .accessibilityIdentifier("checkinSave")
        }
        .padding(Metrics.gutter)
        .screenBackground()
        .presentationDetents([.medium, .large])
        .onAppear {
            value = checkin.value.map { ValueEntrySheet.format($0) } ?? ""
            note = checkin.note ?? ""
            caption = checkin.caption ?? ""
            minutes = checkin.run?.durationMinutes.map { String($0) } ?? ""
            distance = checkin.run?.distanceKm.map { ValueEntrySheet.format($0) } ?? ""
        }
    }
}
