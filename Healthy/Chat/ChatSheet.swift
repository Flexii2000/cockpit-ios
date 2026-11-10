import SwiftUI

/// Der Chat mit der Claude-Instanz auf dem Heimserver (Vertrag §8.2 und §5):
/// ein grosses Blatt ueber dem Dashboard - eigene Fragen rechts, Antworten
/// links, unten das Eingabefeld. Kein Text fuer den leeren Zustand und keine
/// Vorschlaege: das Feld sagt, was hier geht.
///
/// Bewusst nichts aus dem Chat von coHabit: der haengt an dessen Farben,
/// Personen und Abgleich; hier gibt es zwei Seiten und schlichten Text.
struct ChatSheet: View {

    let store: ChatStore

    @State private var input = ""
    @State private var confirmingReset = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private static let bottom = "chat-bottom"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.bubbles) { bubble in
                            ChatBubbleRow(bubble: bubble) { store.retry($0) }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottom)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.bubbles) {
                    withAnimation { proxy.scrollTo(Self.bottom, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmingReset = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.bubbles.isEmpty)
                    .accessibilityLabel("Neuer Chat")
                    .accessibilityIdentifier("chatNew")
                    // Am Knopf, damit die Rueckfrage dort aufgeht. Ohne
                    // „Abbrechen“: daneben tippen tut dasselbe. Der Knopf
                    // darin sagt, was verloren geht.
                    .confirmationDialog("Neuer Chat?", isPresented: $confirmingReset, titleVisibility: .visible) {
                        Button("Chat leeren", role: .destructive) {
                            Task { await store.reset() }
                        }
                    }
                }
            }
            .task { await store.load() }
            .onAppear { store.isVisible = scenePhase == .active }
            .onDisappear { store.isVisible = false }
            .onChange(of: scenePhase) { _, phase in
                store.isVisible = phase == .active
                if phase == .active { Task { await store.load() } }
            }
            // Eine Frage, die der Dienst nicht angenommen hat, kommt zurueck.
            .onChange(of: store.returnedDraft) { _, draft in
                guard let draft else { return }
                if input.isEmpty { input = draft }
                store.returnedDraft = nil
            }
        }
        .presentationDetents([.large])
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Nachricht", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 19))
                .accessibilityIdentifier("chatInput")
            Button {
                let text = input
                input = ""
                store.send(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(store.isBusy || ChatTimeline.question(from: input) == nil)
            .accessibilityLabel("Senden")
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Eine Blase: die Frage rechts in der Akzentfarbe, die Antwort links.
private struct ChatBubbleRow: View {

    let bubble: ChatBubble
    let onRetry: (ChatRetry) -> Void

    var body: some View {
        switch bubble.kind {
        case .question:
            Text(bubble.text)
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 17))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 44)
                .accessibilityIdentifier("chatQuestion")
        case .answer:
            Text(bubble.text)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 28)
                .accessibilityIdentifier("chatAnswer")
        case .progress:
            ProgressView()
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Antwort läuft")
                .accessibilityIdentifier("chatProgress")
        case .failed(let retry):
            Button { onRetry(retry) } label: {
                Label(bubble.text, systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)
            .accessibilityIdentifier("chatFailed")
        }
    }
}
