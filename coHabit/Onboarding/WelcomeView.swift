import SwiftUI

/// Start ohne Zugang (Entwurf S. 11, angepasst nach Vertrag §5.2.11):
/// Logo, Kreise, „Link einfügen" + „Weiter". Kein Apple-/Google-/E-Mail-Login -
/// der Zugang kommt als Link (App-Link, Healthy-Link oder Einladung).
struct WelcomeView: View {

    @State private var text = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var joinCode: String?
    @FocusState private var focused: Bool

    private var session: Session { Session.shared }

    var body: some View {
        ZStack {
            circles
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                CohabitLogo(size: 58)
                    .padding(.bottom, 12)
                HStack(spacing: 8) {
                    InputField(placeholder: "Link einfügen", text: $text, keyboard: .URL,
                               identifier: "linkField", capitalization: .never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.first ?? ""
                        Task { await submit() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Ink.ink)
                    .accessibilityIdentifier("pasteLink")
                }
                if let message = errorMessage ?? session.signedOutReason {
                    Text(message)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.danger)
                        .accessibilityIdentifier("welcomeError")
                }
                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(Ink.onInk) } else { Text("Weiter") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("welcomeNext")
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 26)
        }
        .screenBackground()
        .fullScreenCover(item: Binding(
            get: { joinCode.map { JoinTarget(code: $0) } },
            set: { joinCode = $0?.code })) { target in
            JoinView(code: target.code)
                .presentationBackground(.clear)
        }
        .onChange(of: text) { _, _ in errorMessage = nil }
    }

    private var circles: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Circle().fill(PaletteKey.peach.colors.surface)
                    .frame(width: width * 0.62).position(x: width * 0.12, y: proxy.size.height * 0.2)
                Circle().fill(PaletteKey.butter.colors.surface)
                    .frame(width: width * 0.18).position(x: width * 0.8, y: proxy.size.height * 0.12)
                Circle().fill(PaletteKey.periwinkle.colors.surface)
                    .frame(width: width * 0.44).position(x: width * 0.92, y: proxy.size.height * 0.31)
                Circle().fill(PaletteKey.mint.colors.surface)
                    .frame(width: width * 0.31).position(x: width * 0.38, y: proxy.size.height * 0.43)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func submit() async {
        guard let link = LinkParser.find(in: text) else {
            errorMessage = "Link ungültig"
            return
        }
        if case .join(let code) = link {
            joinCode = code
            return
        }
        guard let token = link.token else {
            errorMessage = "Link ungültig"
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await session.signIn(token: token)
            text = ""
        } catch CohabitError.unauthorized {
            errorMessage = "Link ungültig"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct JoinTarget: Identifiable {
    let code: String
    var id: String { code }
}

/// Einladung ohne Zugang = Registrierung (Vertrag §1.2): Anzeigename,
/// Nutzername, die Zustimmungszeile - der Dienst stellt den Token aus.
struct JoinView: View {
    let code: String

    @State private var preview: InviteLinkPreview?
    @State private var displayName = ""
    @State private var username = ""
    @State private var accepted = false
    @State private var busy = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            ScrollView {
                VStack {
                    Spacer(minLength: 40)
                    if let preview {
                        if let cohabit = preview.cohabit {
                            InvitationCardContent(
                                from: preview.from, cohabit: cohabit, full: preview.full, busy: busy,
                                errorMessage: errorMessage, canAccept: canAccept,
                                decline: { dismiss() }, accept: { Task { await join() } }) {
                                    registration
                                }
                        } else {
                            VStack(spacing: 16) {
                                AvatarView(person: preview.from, size: 64, ring: nil)
                                Text("\(preview.from.displayName) möchte mit dir befreundet sein")
                                    .font(.heading(24))
                                    .multilineTextAlignment(.center)
                                registration
                                if let errorMessage { ErrorLine(message: errorMessage) }
                                HStack(spacing: 12) {
                                    Button("Ablehnen") { dismiss() }.buttonStyle(OutlineButtonStyle(height: 52))
                                    Button("Annehmen") { Task { await join() } }
                                        .buttonStyle(PrimaryButtonStyle())
                                        .disabled(!canAccept || busy)
                                }
                            }
                            .foregroundStyle(Ink.ink)
                            .padding(22)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                        }
                    } else if let errorMessage {
                        VStack(spacing: 16) {
                            Text(errorMessage).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
                            Button("Schließen") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                        }
                        .foregroundStyle(Ink.ink)
                        .padding(24)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    } else {
                        ProgressView()
                            .padding(30)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            do {
                preview = try await CohabitAPI(token: nil, usesCache: false).get("/invite-links/\(code)")
            } catch {
                errorMessage = (error as? CohabitError)?.status == 404
                    ? "Der Link ist abgelaufen." : error.localizedDescription
            }
        }
    }

    private var canAccept: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && Self.isValidUsername(username) && accepted
    }

    /// 3–20 Zeichen `[a-z0-9._]`, beginnt mit Buchstabe (Vertrag §3.2).
    static func isValidUsername(_ name: String) -> Bool {
        name.range(of: "^[a-z][a-z0-9._]{2,19}$", options: .regularExpression) != nil
    }

    private var registration: some View {
        VStack(alignment: .leading, spacing: 10) {
            InputField(placeholder: "Anzeigename", text: Binding(get: { displayName },
                                                                set: { displayName = String($0.prefix(30)) }),
                       identifier: "joinDisplayName")
            InputField(placeholder: "Nutzername", text: Binding(get: { username },
                                                               set: { username = $0.lowercased() }),
                       identifier: "joinUsername", capitalization: .never)
                .autocorrectionDisabled()
            Toggle(isOn: $accepted) {
                Text(Self.termsLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            .toggleStyle(CheckboxToggleStyle())
            .accessibilityIdentifier("joinTerms")
        }
    }

    /// Die Zustimmungszeile mit den beiden Links (Vertrag §1.2).
    static var termsLine: AttributedString {
        let legal = ProfileView.legalURL.absoluteString
        let markdown = "Mit dem Beitritt akzeptierst du die [Nutzungsbedingungen](\(legal)#nutzungsbedingungen) "
            + "und die [Datenschutzerklärung](\(legal)#datenschutz)."
        return (try? AttributedString(markdown: markdown))
            ?? AttributedString("Mit dem Beitritt akzeptierst du die Nutzungsbedingungen und die Datenschutzerklärung.")
    }

    private func join() async {
        busy = true
        defer { busy = false }
        do {
            let result: AcceptResult = try await CohabitAPI(token: nil, usesCache: false).send(
                "POST", "/invite-links/\(code)/accept",
                body: JoinRequest(displayName: displayName.trimmingCharacters(in: .whitespaces),
                                  username: username, acceptTerms: true))
            guard let token = result.token else {
                errorMessage = "Kein Zugang erhalten."
                return
            }
            try await Session.shared.signIn(token: token)
            dismiss()
            if let cohabitId = result.cohabitId {
                Router.shared.showCohabit(cohabitId, section: .overview)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JoinRequest: Encodable {
    let displayName: String
    let username: String
    let acceptTerms: Bool
}

/// Ein Kaestchen statt eines Schalters - fuer die Zustimmungszeile.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                configuration.isOn.toggle()
            } label: {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(configuration.isOn ? Ink.accent : Ink.muted)
            }
            .buttonStyle(.plain)
            configuration.label
        }
    }
}
