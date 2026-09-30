import PhotosUI
import SwiftUI

/// Der Chat (Entwurf S. 7): Check-in-Posts als hervorgehobene Karten,
/// Textblasen (eigene rechts violett), Systemmeldungen klein in der Mitte;
/// unten „Abhaken", das Feld und Senden.
struct ChatView: View {
    let detail: CohabitDetail

    @State private var store: ChatStore
    @State private var text = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var reportTarget: Message?
    @State private var reportReason = ""
    @State private var blockTarget: PersonView?
    @FocusState private var fieldFocused: Bool
    @Environment(\.meId) private var meId

    init(detail: CohabitDetail) {
        self.detail = detail
        _store = State(initialValue: ChatStore(cohabitId: detail.id))
    }

    private var pending: [MessageRequest] {
        CohabitSync.shared.pendingMessages[detail.id] ?? []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.hasMore {
                        ProgressView()
                            .padding(.vertical, 8)
                            .onAppear { Task { await store.loadOlder() } }
                    }
                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || store.messages[index - 1].day != message.day {
                            Text(Formats.dayTitle(message.day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Ink.muted)
                                .padding(.top, 8)
                        }
                        MessageRow(message: message,
                                   showsAuthor: index == 0 || store.messages[index - 1].author?.id != message.author?.id
                                       || store.messages[index - 1].kind != message.kind,
                                   color: detail.ref.color,
                                   react: { reaction in Task { await store.toggle(reaction, on: message) } })
                            .contextMenu { menu(for: message) }
                            .id(message.id)
                    }
                    ForEach(pending, id: \.id) { request in
                        PendingBubble(request: request)
                            .id(request.id)
                    }
                    if store.messages.isEmpty && !store.isLoading && pending.isEmpty {
                        Text("Noch keine Nachrichten")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.muted)
                            .padding(.vertical, 40)
                    }
                    if let message = store.errorMessage, store.messages.isEmpty {
                        ErrorLine(message: message)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .bottom) { inputBar }
            .onChange(of: store.messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: pending.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .task { await store.load() }
        .task(id: "poll") {
            // Push bringt neue Nachrichten ohnehin; solange der Chat offen ist,
            // schaut er zusaetzlich alle zehn Sekunden nach.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled { await store.refresh() }
            }
        }
        .onChange(of: DataBus.shared.revision) { Task { await store.refresh() } }
        .onChange(of: CohabitSync.shared.flushCount) { Task { await store.load() } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
                pickerItem = nil
            }
        }
        .alert("Nachricht melden", isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } })) {
            TextField("Grund", text: $reportReason)
            Button("Melden") {
                if let target = reportTarget {
                    let reason = reportReason.isEmpty ? "ohne Angabe" : reportReason
                    Task { await store.report(target, reason: reason) }
                }
                reportReason = ""
            }
            Button("Abbrechen", role: .cancel) { reportReason = "" }
        }
        .confirmationDialog("\(blockTarget?.displayName ?? "") blockieren?",
                            isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Blockieren", role: .destructive) {
                if let person = blockTarget { Task { await store.block(person) } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func menu(for message: Message) -> some View {
        if !message.deleted && message.kind != .system {
            Menu("Reagieren") {
                ForEach(ReactionKind.allCases) { reaction in
                    let mine = message.reactions.first { $0.reaction == reaction }?.mine ?? false
                    Button {
                        Task { await store.toggle(reaction, on: message) }
                    } label: {
                        if mine { Label(reaction.label, systemImage: "checkmark") } else { Text(reaction.label) }
                    }
                }
            }
        }
        if message.kind == .system {
            ForEach(ReactionKind.allCases) { reaction in
                Button(reaction.label) { Task { await store.toggle(reaction, on: message) } }
            }
        }
        if message.mine && !message.deleted && message.kind != .system {
            Button("Löschen", systemImage: "trash", role: .destructive) {
                Task { await store.delete(message) }
            }
        }
        if !message.mine, message.kind != .system, !message.deleted {
            Button("Melden", systemImage: "exclamationmark.bubble") { reportTarget = message }
            if let author = message.author {
                Button("\(author.displayName) blockieren", systemImage: "hand.raised", role: .destructive) {
                    blockTarget = author
                }
            }
        }
    }

    // MARK: - Eingabe

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let photo {
                HStack {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { self.photo = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Ink.ink)
                            }
                            .offset(x: 8, y: -8)
                            .accessibilityLabel("Foto entfernen")
                        }
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                if detail.summary.canCheckIn && !detail.summary.archived && detail.config.auto == nil {
                    Button {
                        CheckInController.shared.start(CheckInTarget(detail: detail, meId: meId))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: detail.config.photoRequired ? "camera" : "checkmark")
                            Text("Abhaken")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Ink.onInk)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(Ink.ink, in: Capsule())
                    }
                    .accessibilityIdentifier("chatCheckIn")
                }
                HStack(spacing: 4) {
                    TextField("Nachricht", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 16, weight: .medium))
                        .focused($fieldFocused)
                        .accessibilityIdentifier("chatField")
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Foto anhängen")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(minHeight: 50)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                Button {
                    let message = text
                    let image = photo
                    text = ""
                    photo = nil
                    Task {
                        if !(await store.send(text: message, photo: image)) {
                            text = message
                            photo = image
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Ink.accent, in: Circle())
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil)
                .accessibilityLabel("Senden")
                .accessibilityIdentifier("chatSend")
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(Ink.background.opacity(0.96).ignoresSafeArea())
    }
}

extension Message {
    /// Der Kalendertag der Nachricht - in der Zone des Geraets, wie die Uhrzeit.
    var day: CalendarDate { CalendarDate(date: createdAt) }
}

/// Eine Nachricht, je nach Art.
struct MessageRow: View {
    let message: Message
    let showsAuthor: Bool
    let color: PaletteKey
    let react: (ReactionKind) -> Void

    @Environment(\.meId) private var meId

    var body: some View {
        switch message.kind {
        case .system:
            VStack(spacing: 4) {
                Text(message.systemText ?? message.text ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Ink.accentSoft, in: Capsule())
                if !message.reactions.isEmpty {
                    ReactionChips(reactions: message.reactions, react: react)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        case .checkin:
            checkinCard
        case .text, .photo:
            bubble
        }
    }

    private var checkinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let author = message.author {
                    AvatarView(person: author, size: 32, ring: nil)
                    Text("\(Text(author.shortLabel(me: meId)).fontWeight(.heavy)) · hat abgehakt")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                }
                Spacer()
                Text(Formats.time(message.createdAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            if message.deleted {
                Text("Nachricht gelöscht").italic().foregroundStyle(Ink.muted)
            } else {
                if let photo = message.photoId ?? message.checkin?.photoId {
                    PhotoView(id: photo, size: .full, placeholder: color.colors.surface)
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                if let value = message.checkin?.valueText {
                    Text(value)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Ink.ink)
                }
                if let caption = message.checkin?.caption ?? message.text, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.ink)
                }
                if !message.reactions.isEmpty {
                    ReactionChips(reactions: message.reactions, react: react)
                }
            }
        }
        .padding(14)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .padding(.trailing, message.mine ? 0 : 40)
        .padding(.leading, message.mine ? 40 : 0)
        .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post-\(message.id)")
    }

    private var bubble: some View {
        VStack(alignment: message.mine ? .trailing : .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                if !message.mine, showsAuthor, let author = message.author {
                    Text(author.shortLabel(me: meId))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Ink.ink)
                }
                if message.deleted {
                    Text("Nachricht gelöscht")
                        .italic()
                        .font(.system(size: 15))
                        .foregroundStyle(message.mine ? Color.white.opacity(0.8) : Ink.muted)
                } else {
                    if let photo = message.photoId {
                        PhotoView(id: photo, size: .full, placeholder: color.colors.surface)
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if let text = message.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(message.mine ? Color.white : Ink.ink)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.mine ? Color(hex: 0x5B3FD9) : Ink.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if !message.reactions.isEmpty {
                ReactionChips(reactions: message.reactions, react: react)
            }
        }
        .padding(message.mine ? .leading : .trailing, 60)
        .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message-\(message.id)")
    }
}

/// Eine Nachricht, die noch auf Netz wartet.
struct PendingBubble: View {
    let request: MessageRequest

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Ink.muted)
            Text(request.text ?? "Foto")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0x5B3FD9).opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 60)
    }
}

/// „Stark · 2", „Respekt · 1" - antippen setzt oder nimmt die eigene.
struct ReactionChips: View {
    let reactions: [ReactionView]
    let react: (ReactionKind) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(reactions, id: \.reaction) { reaction in
                Button {
                    react(reaction.reaction)
                } label: {
                    Text("\(reaction.label) · \(reaction.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(reaction.mine ? Ink.accentSoft : Ink.track, in: Capsule())
                        .overlay(Capsule().strokeBorder(reaction.mine ? Ink.accent : Color.clear, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reaction-\(reaction.reaction.rawValue)")
            }
        }
    }
}

/// Die vier Reaktionen zur Auswahl - fuer ein Ereignis ohne Reaktionen.
struct AddReactionMenu: View {
    let react: (ReactionKind) -> Void

    var body: some View {
        Menu {
            ForEach(ReactionKind.allCases) { reaction in
                Button(reaction.label) { react(reaction) }
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.muted)
                .frame(width: 34, height: 30)
                .background(Ink.track, in: Capsule())
        }
        .accessibilityLabel("Reagieren")
    }
}
