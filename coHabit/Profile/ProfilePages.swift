import PhotosUI
import SwiftUI
import UIKit

/// Eine Unterseite des Profils: Zurueck, Titel, Inhalt.
struct Subpage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { CircleButtonLabel(systemImage: "chevron.left") }
                        .accessibilityLabel("Zurück")
                    Text(title)
                        .font(.heading(26))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                .padding(.top, 8)
                content
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .statusBarScrim()
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

// MARK: - Profil bearbeiten

struct EditProfileView: View {
    @State private var displayName = ""
    @State private var username = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var session: Session { Session.shared }

    var body: some View {
        Subpage(title: "Profil bearbeiten") {
            if let me = session.me {
                HStack(spacing: 16) {
                    AvatarView(person: me.person, size: 84, ring: nil)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text("Foto wählen")
                        }
                        .buttonStyle(SmallOutlineButtonStyle())
                        if me.person.avatarPhotoId != nil {
                            Button("Foto entfernen", role: .destructive) {
                                Task { await removeAvatar() }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Ink.danger)
                        }
                    }
                }
                FieldLabel(text: "Anzeigename")
                InputField(placeholder: "Anzeigename", text: $displayName, identifier: "displayName")
                FieldLabel(text: "Nutzername")
                InputField(placeholder: "nutzername", text: $username, identifier: "username", capitalization: .never)
                    .autocorrectionDisabled()
                if let errorMessage { ErrorLine(message: errorMessage) }
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().tint(Ink.onInk) } else { Text("Sichern") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving || displayName.trimmingCharacters(in: .whitespaces).isEmpty || username.count < 3)
                .padding(.top, 8)
            }
        }
        .onAppear {
            displayName = session.me?.person.displayName ?? ""
            username = session.me?.person.username ?? ""
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await upload(image)
                }
                pickerItem = nil
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let me: MeView = try await session.api().send("PUT", "/me", body: ProfileRequest(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
            session.store(me)
            errorMessage = nil
            DataBus.shared.changed()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upload(_ image: UIImage) async {
        guard let jpeg = PhotoEncoding.squareAvatar(image) else { return }
        do {
            let me = try await session.api().uploadAvatar(jpeg: jpeg)
            session.store(me)
            DataBus.shared.changed()
        } catch {
            Toast.shared.show(error)
        }
    }

    private func removeAvatar() async {
        do {
            let me: MeView = try await session.api().delete("/me/avatar")
            session.store(me)
            DataBus.shared.changed()
        } catch {
            Toast.shared.show(error)
        }
    }
}

struct ProfileRequest: Encodable {
    let displayName: String
    let username: String
}

// MARK: - Benachrichtigungen

struct NotificationSettingsView: View {
    @State private var settings: NotificationSettings?
    @State private var errorMessage: String?

    var body: some View {
        Subpage(title: "Benachrichtigungen") {
            if let binding = Binding($settings) {
                FormCard {
                    ToggleRow(title: "Check-ins", isOn: binding.checkins)
                    FormDivider()
                    ToggleRow(title: "Beweisfotos", isOn: binding.photos)
                    FormDivider()
                    ToggleRow(title: "Chat", isOn: binding.chat)
                    FormDivider()
                    ToggleRow(title: "Stupser", isOn: binding.nudges)
                    FormDivider()
                    ToggleRow(title: "Einladungen", isOn: binding.invites)
                }
                FormCard {
                    ToggleRow(title: "Erinnerungen", isOn: binding.reminders)
                    FormDivider()
                    ToggleRow(title: "Gefährdete Streaks", isOn: binding.streakAtRisk)
                    FormDivider()
                    ToggleRow(title: "Challenge-Ende", isOn: binding.challengeEnd)
                }
            } else if let errorMessage {
                ErrorLine(message: errorMessage)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .task {
            do {
                settings = try await Session.shared.api().get("/me/notifications")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: settings) { old, new in
            guard old != nil, let new else { return }
            Task {
                do {
                    let saved: NotificationSettings = try await Session.shared.api().send("PUT", "/me/notifications", body: new)
                    if saved != settings { settings = saved }
                } catch {
                    Toast.shared.show(error)
                }
            }
        }
    }
}

// MARK: - Health-Verbindung

struct HealthConnectionView: View {
    @State private var details: [CohabitDetail] = []
    @State private var loading = true
    @State private var asked = false

    private var health: CohabitHealthSync { CohabitHealthSync.shared }

    var body: some View {
        Subpage(title: "Health-Verbindung") {
            FormCard {
                HStack {
                    Text("Apple Health")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    if !health.isAvailable {
                        RowValue(text: "nicht verfügbar")
                    } else if asked {
                        Chip(text: "verbunden", fill: PaletteKey.mint.colors.surface, weight: .bold, size: 12)
                    } else {
                        Button("Verbinden") {
                            Task {
                                await health.requestAuthorization()
                                asked = await health.hasAsked()
                            }
                        }
                        .buttonStyle(SmallOutlineButtonStyle())
                    }
                }
                .frame(minHeight: 56)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if !details.isEmpty {
                SectionLabel(text: "Co-Habits mit Health")
                FormCard {
                    ForEach(Array(details.enumerated()), id: \.element.id) { index, detail in
                        if index > 0 { FormDivider() }
                        Toggle(isOn: Binding(
                            get: { detail.mySettings.healthConsent },
                            set: { value in Task { await setConsent(value, for: detail) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.ref.name)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Ink.ink)
                                Text(detail.health?.label ?? "")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        .tint(Ink.accent)
                        .frame(minHeight: 60)
                        // kcal aus Healthy: zustimmen kann nur, wer einen Healthy-Zugang hat.
                        .disabled(detail.health?.isFromHealthy == true && !HealthyAccess.isAvailable)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        asked = await health.hasAsked()
        let api = Session.shared.api()
        guard let list: [CohabitSummary] = try? await api.get("/cohabits") else {
            loading = false
            return
        }
        var found: [CohabitDetail] = []
        for summary in list {
            if let detail: CohabitDetail = try? await api.get("/cohabits/\(summary.id)"), detail.config.health != nil {
                CohabitHealthSync.shared.update(from: detail)
                found.append(detail)
            }
        }
        details = found
        loading = false
    }

    private func setConsent(_ value: Bool, for detail: CohabitDetail) async {
        // kcal aus Healthy holt der Dienst - dafuer keine Apple-Health-Abfrage.
        let fromDevice = !(detail.health?.isFromHealthy ?? false)
        if value && fromDevice { await health.requestAuthorization() }
        var settings = detail.mySettings
        settings.healthConsent = value
        do {
            let updated: CohabitDetail = try await Session.shared.api().send("PUT", "/cohabits/\(detail.id)/settings/me", body: settings)
            CohabitHealthSync.shared.update(from: updated)
            if let index = details.firstIndex(where: { $0.id == detail.id }) { details[index] = updated }
            if value && fromDevice { await health.sync(only: detail.id) }
            asked = await health.hasAsked()
        } catch {
            Toast.shared.show(error)
        }
    }
}

// MARK: - Archiv

struct ArchivedView: View {
    @State private var list: [CohabitSummary]?
    @State private var errorMessage: String?

    var body: some View {
        Subpage(title: "Archivierte Co-Habits") {
            if let list {
                if list.isEmpty {
                    EmptyState(text: "Nichts archiviert")
                } else {
                    ForEach(list) { summary in
                        NavigationLink(value: Route.cohabit(summary.id, .overview)) {
                            HStack {
                                Text(summary.headline.short)
                                    .font(.system(size: 20, weight: .black))
                                    .frame(width: 76, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.ref.name).font(.system(size: 17, weight: .heavy))
                                    Text(summary.typeLine).font(.system(size: 13, weight: .medium))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Ink.ink)
                            .card(summary.ref.typeColor.colors.surface, padding: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let errorMessage {
                ErrorLine(message: errorMessage)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .task {
            do {
                list = try await Session.shared.api().get("/me/archived")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Export

struct ExportView: View {
    @State private var file: URL?
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Subpage(title: "Daten exportieren") {
            if let errorMessage { ErrorLine(message: errorMessage) }
            if let file {
                ShareLink(item: file) {
                    Label("Export teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    Task { await export() }
                } label: {
                    if working { ProgressView().tint(Ink.onInk) } else { Text("Export erstellen") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
            }
        }
    }

    private func export() async {
        working = true
        defer { working = false }
        do {
            let data = try await Session.shared.api().data("/me/export")
            let url = FileManager.default.temporaryDirectory.appending(path: "coHabit-Export-\(CalendarDate.today().iso).zip")
            try data.write(to: url, options: .atomic)
            file = url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - App verbinden

struct AppLinksView: View {
    @State private var links: [AppLink]?
    @State private var label = UIDevice.current.name
    @State private var created: CreatedAppLink?
    @State private var errorMessage: String?
    @State private var sharing: ShareItem?

    var body: some View {
        Subpage(title: "App verbinden") {
            if let created {
                VStack(alignment: .leading, spacing: 10) {
                    Text(created.label)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Ink.ink)
                    Text(created.setupUrl)
                        .font(.system(size: 13, weight: .medium).monospaced())
                        .foregroundStyle(Ink.ink)
                        .textSelection(.enabled)
                    HStack {
                        Button("Kopieren") {
                            UIPasteboard.general.string = created.setupUrl
                            Toast.shared.show("Kopiert")
                        }
                        .buttonStyle(SmallOutlineButtonStyle())
                        Button("Teilen") {
                            if let url = URL(string: created.setupUrl) { sharing = ShareItem(url: url) }
                        }
                        .buttonStyle(SmallOutlineButtonStyle())
                    }
                }
                .card(Ink.accentSoft, padding: 16)
            }
            FormCard {
                HStack {
                    TextField("Name des Geräts", text: $label)
                        .font(.system(size: 17, weight: .medium))
                    Button("Link erzeugen") { Task { await create() } }
                        .buttonStyle(SmallOutlineButtonStyle())
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(minHeight: 60)
            }
            if let errorMessage { ErrorLine(message: errorMessage) }
            if let links, !links.isEmpty {
                SectionLabel(text: "Verbundene Geräte")
                FormCard {
                    ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                        if index > 0 { FormDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.label)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Ink.ink)
                                Text(link.lastUsedAt.map { "zuletzt " + Formats.relativeStamp($0) } ?? "noch nicht benutzt")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Ink.muted)
                            }
                            Spacer()
                            Button("Widerrufen", role: .destructive) { Task { await revoke(link) } }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Ink.danger)
                        }
                        .frame(minHeight: 60)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url]).presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        do {
            links = try await Session.shared.api().get("/me/app-links")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        do {
            created = try await Session.shared.api().send("POST", "/me/app-links",
                                                           body: LabelRequest(label: label.trimmingCharacters(in: .whitespaces)))
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    private func revoke(_ link: AppLink) async {
        do {
            try await Session.shared.api().sendIgnoringResponse("DELETE", "/me/app-links/\(link.id)")
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }
}

struct LabelRequest: Encodable {
    let label: String
}
