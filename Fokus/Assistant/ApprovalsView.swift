import LocalAuthentication
import SwiftUI
import UIKit

/// Freigaben des Assistenten: Mails (spaeter Ueberweisungen), die erst nach
/// Face ID rausgehen. Erreichbar ueber den Push und das Menue im To-Do-Tab.
struct ApprovalsView: View {

    /// Aus einem Push: diese Freigabe gleich oeffnen.
    let openID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ApprovalSummary] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var path: [String] = []
    @State private var showsKey = false
    @State private var showsRecipients = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                let open = items.filter { $0.status == .wartet }
                let done = items.filter { $0.status != .wartet }
                if !open.isEmpty {
                    Section("Offen") { ForEach(open) { row($0) } }
                }
                if !done.isEmpty {
                    Section("Erledigt") { ForEach(done) { row($0) } }
                }
            }
            .overlay {
                if loaded && items.isEmpty && error == nil {
                    ContentUnavailableView("Keine Freigaben", systemImage: "checkmark.shield")
                }
            }
            .navigationTitle("Freigaben")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                ApprovalDetailView(id: id) { Task { await load() } }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showsRecipients = true } label: { Label("Empfänger", systemImage: "person.2") }
                        Button { showsKey = true } label: { Label("Schlüssel", systemImage: "key") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable { await load() }
            .task {
                if let openID, path.isEmpty { path = [openID] }
                await load()
            }
            .sheet(isPresented: $showsKey) { ApprovalKeyView() }
            .sheet(isPresented: $showsRecipients) { ApprovalRecipientsView() }
        }
    }

    private func row(_ item: ApprovalSummary) -> some View {
        NavigationLink(value: item.id) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.titel).lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.status.label)
                        .foregroundStyle(item.status.tint)
                    Text(item.erstellt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
    }

    private func load() async {
        guard let api = ApprovalsAPI.live() else {
            error = ApprovalsAPI.Failure.noAccess.localizedDescription
            loaded = true
            return
        }
        do {
            items = try await api.list()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// Der ganze Auftrag, so wie er signiert wird - jedes Feld, ungekuerzt.
struct ApprovalDetailView: View {

    let id: String
    var onChange: () -> Void = {}

    @State private var detail: ApprovalDetail?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmReject = false
    private let hasKey = ApprovalKey.publicKeyDER() != nil

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let detail {
                Section {
                    LabeledContent("Status") {
                        Text(detail.status.label).foregroundStyle(detail.status.tint)
                    }
                    LabeledContent("Angelegt") {
                        Text(detail.erstellt, format: .dateTime.day().month().hour().minute())
                    }
                }
                ForEach(detail.felder.filter { !$0.wert.isEmpty }, id: \.name) { field in
                    Section(ApprovalDetailView.label(field.name)) {
                        Text(field.wert)
                            .textSelection(.enabled)
                            .font(["iban", "liste"].contains(field.name) ? .body.monospaced() : .body)
                    }
                }
                if let ergebnis = detail.ergebnis, !ergebnis.isEmpty {
                    Section("Ergebnis") { Text(ergebnis).textSelection(.enabled) }
                }
                if detail.localHash != detail.hash {
                    Section {
                        Text("Inhalt passt nicht zur Prüfsumme des Servers – nicht freigeben.")
                            .foregroundStyle(.red)
                    }
                } else if detail.status == .wartet {
                    Section {
                        Button {
                            Task { await approve(detail) }
                        } label: {
                            Label("Mit Face ID freigeben", systemImage: "faceid")
                        }
                        .disabled(busy || !hasKey)
                        Button("Ablehnen", role: .destructive) { confirmReject = true }
                            .disabled(busy)
                    } footer: {
                        if !hasKey { Text("Erst unter „Schlüssel“ einen Schlüssel erzeugen.") }
                    }
                }
            } else if error == nil {
                Section { ProgressView() }
            }
        }
        .navigationTitle(detail.map { ApprovalDetailView.title($0.art) } ?? "Freigabe")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Ablehnen?", isPresented: $confirmReject, titleVisibility: .visible) {
            Button("Ablehnen", role: .destructive) { Task { await reject() } }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    nonisolated static func label(_ name: String) -> String {
        switch name {
        case "an": "An"
        case "cc": "Cc"
        case "betreff": "Betreff"
        case "text": "Text"
        case "antwortAuf": "Antwort auf"
        case "name": "Empfänger"
        case "iban": "IBAN"
        case "betrag": "Betrag"
        case "zweck": "Verwendungszweck"
        case "ausfuehrung": "Ausführung"
        case "liste": "Empfänger"
        case "anzahl": "Anzahl"
        default: name
        }
    }

    nonisolated static func title(_ art: String) -> String {
        switch art {
        case "mail": "Mail"
        case "ueberweisung": "Überweisung"
        case "empfaenger": "Empfänger"
        case "empfaengerliste": "Empfängerliste"
        default: "Freigabe"
        }
    }

    private func load() async {
        guard let api = ApprovalsAPI.live() else {
            error = ApprovalsAPI.Failure.noAccess.localizedDescription
            return
        }
        do {
            detail = try await api.detail(id: id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func approve(_ detail: ApprovalDetail) async {
        guard let api = ApprovalsAPI.live() else { return }
        busy = true
        defer { busy = false }
        do {
            // Selbst gerechneter Hash: die Signatur gilt fuer das Angezeigte.
            let time = Int64(Date().timeIntervalSince1970)
            let message = ApprovalPayload.message(id: detail.id, hash: detail.localHash, time: time)
            let signature = try await ApprovalKey.sign(
                message, reason: "\(ApprovalDetailView.title(detail.art)) freigeben: \(detail.titel)")
            self.detail = try await api.approve(id: detail.id, time: time, signature: signature)
            error = nil
            onChange()
            await followUntilDone(api)
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel {
            // Abgebrochen - nichts passiert.
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Das Gate fuehrt im Hintergrund aus; mitlesen, bis es fertig ist. Eine
    /// Ueberweisung dauert Minuten (Anmeldung, pushTAN) - der Zwischenstand
    /// steht solange im Ergebnis ("Wartet auf deine Freigabe …").
    private func followUntilDone(_ api: ApprovalsAPI) async {
        let transfer = detail?.art == "ueberweisung"
        for _ in 0..<(transfer ? 300 : 20) {
            guard detail?.status == .freigegeben, !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(transfer ? 2 : 1.5))
            if let fresh = try? await api.detail(id: id) { detail = fresh }
        }
        onChange()
    }

    private func reject() async {
        guard let api = ApprovalsAPI.live() else { return }
        busy = true
        defer { busy = false }
        do {
            detail = try await api.reject(id: id)
            error = nil
            onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Die Empfaengerliste fuer Ueberweisungen: nur an diese IBANs kann der
/// Assistent eine Ueberweisung vorschlagen. Hinzu kommt ein Empfaenger nur
/// ueber eine Freigabe; entfernen geht hier ohne Face ID - das nimmt nur Rechte.
struct ApprovalRecipientsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [ApprovalRecipient] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var pendingDelete: ApprovalRecipient?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                ForEach(recipients) { recipient in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipient.name)
                        Text(ApprovalRecipient.format(iban: recipient.iban))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .swipeActions {
                        Button("Entfernen", role: .destructive) { pendingDelete = recipient }
                    }
                }
            }
            .overlay {
                if loaded && recipients.isEmpty && error == nil {
                    ContentUnavailableView("Keine Empfänger", systemImage: "person.2")
                }
            }
            .navigationTitle("Empfänger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog(pendingDelete.map { "\($0.name) entfernen?" } ?? "",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    if let target = pendingDelete { Task { await delete(target) } }
                }
            }
        }
    }

    private func load() async {
        guard let api = ApprovalsAPI.live() else {
            error = ApprovalsAPI.Failure.noAccess.localizedDescription
            loaded = true
            return
        }
        do {
            recipients = try await api.recipients()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func delete(_ recipient: ApprovalRecipient) async {
        pendingDelete = nil
        guard let api = ApprovalsAPI.live() else { return }
        do {
            try await api.deleteRecipient(iban: recipient.iban)
            recipients.removeAll { $0.iban == recipient.iban }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Der oeffentliche Schluessel zum Eintragen auf dem Server
/// (`setup-gate.sh --key`) und sein Fingerabdruck zum Vergleichen.
struct ApprovalKeyView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: Data? = ApprovalKey.publicKeyDER()
    @State private var error: String?
    @State private var confirmReplace = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !ApprovalKey.isAvailable {
                    Section { Text(ApprovalKey.Failure.unavailable.localizedDescription) }
                } else if let publicKey {
                    let base64 = publicKey.base64EncodedString()
                    Section {
                        Text(base64)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button(copied ? "Kopiert" : "Kopieren") {
                            UIPasteboard.general.string = base64
                            copied = true
                        }
                        ShareLink(item: base64)
                    } header: {
                        Text("Öffentlicher Schlüssel")
                    } footer: {
                        Text("Auf dem Server: setup-gate.sh --key")
                    }
                    Section("Fingerabdruck") {
                        Text(ApprovalPayload.fingerprint(publicKeyDER: publicKey))
                            .font(.body.monospaced())
                    }
                    Section {
                        Button("Neuen Schlüssel erzeugen", role: .destructive) { confirmReplace = true }
                    }
                } else {
                    Section {
                        Button("Schlüssel erzeugen") { create() }
                    }
                }
            }
            .navigationTitle("Schlüssel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Neuer Schlüssel?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Ersetzen", role: .destructive) { create() }
            } message: {
                Text("Der alte gilt dann nicht mehr; der neue muss auf dem Server eingetragen werden.")
            }
        }
    }

    private func create() {
        do {
            publicKey = try ApprovalKey.create()
            copied = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ApprovalStatus {
    var tint: Color {
        switch self {
        case .wartet: .orange
        case .freigegeben: .blue
        case .ausgefuehrt: .green
        case .fehler: .red
        case .abgelehnt, .abgelaufen, .unbekannt: .secondary
        }
    }
}
