import Foundation

// GIFs im Chat (Vertrag §2.7a): aus der Suche von KLIPY oder eigene Dateien.
// Die Suche laeuft direkt vom Geraet zu KLIPY (deren Bedingung) - der Dienst
// liefert nur den Schluessel (`GET /gifs/config`) und speichert, was gesendet
// wurde (`GifView` in der Nachricht).

/// Ein GIF aus der Suche in einer Nachricht (`kind: GIF`).
struct GifView: Codable, Hashable, Sendable {
    /// `KLIPY`.
    let provider: String?
    let slug: String
    let title: String?
    let width: Int
    let height: Int
    let gifUrl: String
    let webpUrl: String?
    let mp4Url: String?
    let stillUrl: String?

    /// Seitenverhaeltnis Hoehe zu Breite - 1, wenn eine Angabe fehlt.
    var aspect: Double {
        width > 0 && height > 0 ? Double(height) / Double(width) : 1
    }
}

/// Was die App beim Senden schickt (`"gif"` in `POST …/messages`): die Felder
/// aus `file.md` des KLIPY-Eintrags. Liegt auch im Postausgang.
///
/// Alle Schluessel stehen da, leere als `null` - wie im Vertrag.
struct GifInput: Codable, Hashable, Sendable {
    let slug: String
    let title: String?
    let width: Int
    let height: Int
    let gifUrl: String
    let webpUrl: String?
    let mp4Url: String?
    let stillUrl: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(gifUrl, forKey: .gifUrl)
        try c.encode(webpUrl, forKey: .webpUrl)
        try c.encode(mp4Url, forKey: .mp4Url)
        try c.encode(stillUrl, forKey: .stillUrl)
    }
}

/// `GET /gifs/config`: ohne Schluessel auf dem Server `{"enabled":false}` -
/// dann gibt es keinen GIF-Knopf (eigene GIFs gehen weiter).
struct GifConfig: Codable, Hashable, Sendable {
    let enabled: Bool
    let apiKey: String?
    /// Eine zufaellige, stabile Kennung je Person fuer KLIPYs `customer_id`.
    let customerId: String?
    let locale: String?
    let contentFilter: String?

    init(enabled: Bool, apiKey: String? = nil, customerId: String? = nil, locale: String? = nil,
         contentFilter: String? = nil) {
        self.enabled = enabled
        self.apiKey = apiKey
        self.customerId = customerId
        self.locale = locale
        self.contentFilter = contentFilter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        customerId = try c.decodeIfPresent(String.self, forKey: .customerId)
        locale = try c.decodeIfPresent(String.self, forKey: .locale)
        contentFilter = try c.decodeIfPresent(String.self, forKey: .contentFilter)
    }

    /// Ob die Suche geht: an und mit Schluessel.
    var isUsable: Bool { enabled && !(apiKey ?? "").isEmpty }
}

// MARK: - KLIPY

/// Eine Seite aus `…/gifs/trending` bzw. `…/gifs/search`:
/// `{"result":true,"data":{"data":[Item],"current_page":1,"per_page":24,"has_next":true}}`.
struct KlipyPage: Decodable, Sendable {
    let items: [KlipyItem]
    let currentPage: Int
    let hasNext: Bool

    private enum Keys: String, CodingKey { case data }
    private enum DataKeys: String, CodingKey {
        case data
        case currentPage = "current_page"
        case hasNext = "has_next"
    }

    init(items: [KlipyItem], currentPage: Int, hasNext: Bool) {
        self.items = items
        self.currentPage = currentPage
        self.hasNext = hasNext
    }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Keys.self)
        let data = try outer.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        // Einzeln, damit ein unlesbarer Eintrag nicht die ganze Seite kippt;
        // Eintraege ohne `file` fallen weg (Vertrag).
        let raw = try data.decodeIfPresent([Lenient<KlipyItem>].self, forKey: .data) ?? []
        items = raw.compactMap(\.value).filter { !$0.file.isEmpty }
        currentPage = try data.decodeIfPresent(Int.self, forKey: .currentPage) ?? 1
        hasNext = try data.decodeIfPresent(Bool.self, forKey: .hasNext) ?? false
    }
}

/// Ein Eintrag der Suche.
struct KlipyItem: Decodable, Hashable, Sendable, Identifiable {
    /// Bei KLIPY eine Zahl - hier als Text, damit auch eine Zeichenkette passt.
    let id: String
    let slug: String
    let title: String?
    /// `data:image/jpeg;base64,…` - der Platzhalter, bis das GIF da ist.
    let blurPreview: String?
    /// Groesse (`hd`, `md`, `sm`, `xs`) → Format (`gif`, `webp`, `jpg`, `mp4`, `webm`).
    let file: [String: [String: KlipyMedia]]

    struct KlipyMedia: Decodable, Hashable, Sendable {
        let url: String
        let width: Int?
        let height: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, file
        case blurPreview = "blur_preview"
    }

    init(id: String, slug: String, title: String?, blurPreview: String?, file: [String: [String: KlipyMedia]]) {
        self.id = id
        self.slug = slug
        self.title = title
        self.blurPreview = blurPreview
        self.file = file
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? c.decode(Int64.self, forKey: .id) {
            id = String(number)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        blurPreview = try c.decodeIfPresent(String.self, forKey: .blurPreview)
        // Groessen und Formate einzeln: ein Format in unerwarteter Form
        // (leer, null) soll nur dieses eine ausfallen lassen.
        var file: [String: [String: KlipyMedia]] = [:]
        if let sizes = try? c.decode([String: [String: Lenient<KlipyMedia>]].self, forKey: .file) {
            for (size, formats) in sizes {
                let usable = formats.compactMapValues(\.value)
                if !usable.isEmpty { file[size] = usable }
            }
        }
        self.file = file
    }

    /// Fuer die Kachel im Raster: `sm` animiert (`webp`, sonst `gif`) - fehlt
    /// `sm`, die naechste Groesse.
    var tileURL: URL? {
        for size in ["sm", "xs", "md", "hd"] {
            guard let formats = file[size] else { continue }
            if let url = (formats["webp"] ?? formats["gif"]).flatMap({ URL(string: $0.url) }) { return url }
        }
        return nil
    }

    /// Die Daten hinter `blur_preview`.
    var blurPreviewData: Data? {
        guard let blurPreview, blurPreview.hasPrefix("data:"),
              let comma = blurPreview.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(blurPreview[blurPreview.index(after: comma)...]))
    }

    /// Was gesendet wird: `md`, fehlt das, `hd`, dann `sm` - jeweils nur mit
    /// einem `gif` (Pflicht beim Dienst). Groesse aus dem `gif` der Stufe.
    var gifInput: GifInput? {
        for size in ["md", "hd", "sm"] {
            guard let formats = file[size], let gif = formats["gif"] else { continue }
            let width = gif.width ?? formats.values.compactMap(\.width).first ?? 0
            let height = gif.height ?? formats.values.compactMap(\.height).first ?? 0
            guard width > 0, height > 0 else { continue }
            return GifInput(slug: slug, title: title.map { String($0.prefix(200)) }, width: width, height: height,
                            gifUrl: gif.url, webpUrl: formats["webp"]?.url, mp4Url: formats["mp4"]?.url,
                            stillUrl: formats["jpg"]?.url)
        }
        return nil
    }
}

/// Liest einen Wert, ohne bei einem kaputten Eintrag den ganzen Rest zu verlieren.
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
