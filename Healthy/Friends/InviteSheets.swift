import SwiftUI

/// „Code erstellen“ (Vertrag §10.4): der Code gross, darunter Teilen. Ein noch
/// offener Code steht wieder da, statt bei jedem Oeffnen ein neuer.
struct InviteCodeSheet: View {

    let store: FriendsStore

    @State private var code: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let code {
                    Text(code)
                        .font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("inviteCode")
                    ShareLink(item: FriendsFormat.shareText(code: code)) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                code = await store.inviteCode()
                // Ging es nicht, steht der Grund als Meldung oben - das leere
                // Blatt hat dann nichts zu zeigen.
                if code == nil { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}

/// „Code eingeben“: der Code eines Freundes - getippt oder samt Nachricht
/// eingefuegt (`FriendCode.parse`). Was nicht ging, steht unter dem Feld.
struct EnterCodeSheet: View {

    let store: FriendsStore

    @State private var input = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code", text: $input)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { accept() }
                        .accessibilityIdentifier("friendCode")
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("friendCodeError")
                    }
                }
            }
            // Kurz: zwischen „Abbrechen“ und „Hinzufügen“ passt nicht mehr.
            .navigationTitle("Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { accept() }
                        .disabled(FriendCode.parse(input) == nil || isWorking)
                }
            }
            .onAppear { focused = true }
            .onChange(of: input) { error = nil }
        }
        .presentationDetents([.medium])
    }

    private func accept() {
        guard let code = FriendCode.parse(input), !isWorking else { return }
        isWorking = true
        Task {
            let failure = await store.accept(code: code)
            isWorking = false
            if let failure {
                error = failure
            } else {
                dismiss()
            }
        }
    }
}
