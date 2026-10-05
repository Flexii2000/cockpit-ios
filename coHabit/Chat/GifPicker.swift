import SwiftUI
import UIKit

/// Die Suche bei KLIPY (Vertrag §2.7a) - direkt vom Geraet, nicht ueber den
/// Dienst (KLIPYs Bedingung). Schluessel, Kennung, Sprache und Filter kommen
/// aus `GET /gifs/config`.
struct KlipyClient: Sendable {
    let apiKey: String
    let customerId: String
    let locale: String?
    let contentFilter: String?
    var session: URLSession = KlipyMedia.session

    static var base: URL {
        #if DEBUG
        // Wie COCKPIT_URL_<DIENST>: gegen einen Stub (tools/klipy-stub.py) -
        // ohne echten Schluessel antwortet KLIPY nicht.
        if let override = ProcessInfo.processInfo.environment["COCKPIT_URL_KLIPY"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://api.klipy.com/api/v1")!
    }
    static let perPage = 24

    /// Nur mit eingeschalteter Suche und Schluessel.
    init?(config: GifConfig?, session: URLSession = KlipyMedia.session) {
        guard let config, config.isUsable, let apiKey = config.apiKey else { return nil }
        self.apiKey = apiKey
        customerId = config.customerId ?? ""
        locale = config.locale
        contentFilter = config.contentFilter
        self.session = session
    }

    /// Leeres Suchfeld: `trending`, sonst `search?q=…` - immer mit
    /// `customer_id`, `locale`, `content_filter` und 24 je Seite.
    func url(query: String, page: Int) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = trimmed.isEmpty ? "trending" : "search"
        var components = URLComponents(url: Self.base.appending(path: apiKey).appending(path: "gifs").appending(path: endpoint),
                                       resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        items += [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(Self.perPage)),
            URLQueryItem(name: "customer_id", value: customerId),
        ]
        if let locale { items.append(URLQueryItem(name: "locale", value: locale)) }
        if let contentFilter { items.append(URLQueryItem(name: "content_filter", value: contentFilter)) }
        components.queryItems = items
        return components.url!
    }

    func page(query: String, page: Int) async throws -> KlipyPage {
        var request = URLRequest(url: url(query: query, page: page))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Die Ergebnisse aendern sich ueber den Tag - nicht aus dem Cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(KlipyPage.self, from: data)
    }

    /// Nach dem Senden, feuern und vergessen (Vertrag: `share/{slug}` mit dem
    /// Suchbegriff, leer bei Trending).
    func shareRequest(slug: String, query: String) -> URLRequest {
        var request = URLRequest(url: Self.base.appending(path: apiKey).appending(path: "gifs")
            .appending(path: "share").appending(path: slug))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["customer_id": customerId,
                                                      "q": query.trimmingCharacters(in: .whitespacesAndNewlines)])
        return request
    }

    func share(slug: String, query: String) async {
        _ = try? await session.data(for: shareRequest(slug: slug, query: query))
    }
}

/// Was das GIF-Blatt zeigt: Trending bei leerem Feld, sonst die Suche - in der
/// Reihenfolge von KLIPY, nachgeladen beim Scrollen, solange `has_next`.
@MainActor
@Observable
final class GifSearchStore {
    private(set) var items: [KlipyItem] = []
    private(set) var hasNext = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Der Suchbegriff der gezeigten Ergebnisse - geht beim Teilen mit.
    private(set) var query = ""
    private(set) var loaded = false

    private var page = 1
    /// Eine Antwort, die eine neuere Suche ueberholt hat, wird verworfen.
    private var generation = 0
    let client: KlipyClient

    init(client: KlipyClient) {
        self.client = client
    }

    func search(_ text: String) async {
        generation += 1
        let current = generation
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let result = try await client.page(query: query, page: 1)
            guard current == generation else { return }
            items = result.items
            hasNext = result.hasNext
            page = 1
            errorMessage = nil
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            items = []
            hasNext = false
            errorMessage = "KLIPY ist nicht erreichbar."
        }
        loaded = true
    }

    func loadMore() async {
        guard hasNext, !isLoading else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        guard let result = try? await client.page(query: query, page: page + 1), current == generation else { return }
        items += result.items
        hasNext = result.hasNext
        page += 1
    }
}

/// Das GIF-Blatt: Suchfeld oben („Search KLIPY", Pflicht), darunter ein
/// Raster in zwei Spalten. Antippen sendet sofort und schliesst das Blatt.
struct GifPickerSheet: View {
    let pick: (KlipyItem, String) -> Void

    @State private var store: GifSearchStore
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    init(client: KlipyClient, pick: @escaping (KlipyItem, String) -> Void) {
        self.pick = pick
        _store = State(initialValue: GifSearchStore(client: client))
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                    TextField("Search KLIPY", text: $text)
                        .font(.system(size: 16, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("gifSearch")
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Ink.muted)
                        }
                        .accessibilityLabel("Leeren")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Ink.surface, in: Capsule())
                Button { dismiss() } label: {
                    CircleButtonLabel(systemImage: "xmark", size: 40, fill: Ink.accentSoft)
                }
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("sheetClose")
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(store.items.enumerated()), id: \.offset) { index, item in
                        Button {
                            pick(item, store.query)
                            dismiss()
                        } label: {
                            GifTile(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gifTile-\(index)")
                        .onAppear {
                            if index >= store.items.count - 6 { Task { await store.loadMore() } }
                        }
                    }
                }
                if store.isLoading {
                    ProgressView().padding(.vertical, 24)
                } else if let message = store.errorMessage {
                    ErrorLine(message: message).padding(.top, 12)
                } else if store.loaded && store.items.isEmpty {
                    Text("Nichts gefunden")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.muted)
                        .padding(.vertical, 40)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 18)
        .screenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: text) {
            // 300 ms nach dem letzten Tastendruck; das leere Feld sofort.
            if !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            await store.search(text)
        }
    }
}

/// Eine Kachel: quadratisch beschnitten, `sm` animiert, bis dahin `blur_preview`.
struct GifTile: View {
    let item: KlipyItem

    @State private var preview: UIImage?
    @State private var animated: Data?
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Ink.track
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    }
                    if let animated, let url = item.tileURL {
                        AnimatedImageView(data: animated, key: url.absoluteString, animates: visible && !reduceMotion)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: item.tileURL) {
                preview = item.blurPreviewData.flatMap(UIImage.init(data:))
                guard let url = item.tileURL else { return }
                animated = await KlipyMedia.shared.data(url)
            }
            .accessibilityElement()
            .accessibilityLabel(item.title.map { "GIF: \($0)" } ?? "GIF")
    }
}
