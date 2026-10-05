import ImageIO
import SwiftUI
import UIKit

// Animierte Bilder im Chat und im GIF-Blatt (Vertrag §2.7a).
//
// Alles laeuft ueber ImageIO (`CGAnimateImageDataWithBlock`): GIF und WebP,
// Bild fuer Bild dekodiert, wenn es dran ist - nie alle Bilder auf einmal im
// Speicher wie bei `UIImage.animatedImage`. Ausserhalb des Fensters haelt die
// Animation an. Ein Video (mp4 als stumme Schleife) waere kleiner, braucht
// aber je Nachricht einen AVPlayer samt Audio-Sitzung - siehe
// docs/ENTSCHEIDUNGEN.md (05.10.).

/// Ein animiertes Bild aus Daten. `key` sagt, ob sich die Daten geaendert
/// haben (Daten zu vergleichen hiesse, sie Byte fuer Byte durchzugehen).
struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    let key: String
    var animates = true

    func makeUIView(context: Context) -> AnimatedImageUIView { AnimatedImageUIView() }

    func updateUIView(_ view: AnimatedImageUIView, context: Context) {
        view.show(data, key: key, animates: animates)
    }

    static func dismantleUIView(_ view: AnimatedImageUIView, coordinator: ()) {
        view.stop()
    }
}

final class AnimatedImageUIView: UIView {
    private let imageView = UIImageView()
    private var data: Data?
    private var key: String?
    private var animates = true
    /// Zaehlt jeden Start - ein laufender Block mit einer alten Nummer haelt an.
    private var run = 0

    init() {
        super.init(frame: .zero)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Keine eigene Groesse: den Rahmen bestimmt SwiftUI.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func show(_ data: Data, key: String, animates: Bool) {
        guard key != self.key || animates != self.animates else { return }
        self.data = data
        self.key = key
        self.animates = animates
        restart()
    }

    func stop() {
        run += 1
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { restart() }
    }

    private func restart() {
        run += 1
        guard let data, window != nil else { return }
        guard animates else {
            imageView.image = UIImage(data: data)
            return
        }
        let current = run
        let status = CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
            // ImageIO ruft auf der Hauptschlange.
            MainActor.assumeIsolated {
                guard let self, self.run == current else {
                    stop.pointee = true
                    return
                }
                self.imageView.image = UIImage(cgImage: image)
            }
        }
        if status != noErr {
            imageView.image = UIImage(data: data)
        }
    }
}

/// Medien von KLIPY: direkt vom Geraet geladen und nur im Speicher bzw. im
/// HTTP-Cache des Systems gehalten - nie als eigene Datei (KLIPYs
/// Bedingungen, Vertrag §2.7a). Die URLs gehen unveraendert raus.
@MainActor
final class KlipyMedia {

    static let shared = KlipyMedia()

    /// Eine eigene Sitzung mit einem groesseren HTTP-Cache als dem geteilten
    /// (512 KB Speicher, 10 MB Platte - ein GIF waere jedes Mal neu zu holen).
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "KlipyHTTPCache")
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024,
                                          directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private let memory: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private var running: [URL: Task<Data?, Never>] = [:]

    func cached(_ url: URL) -> Data? {
        memory.object(forKey: url as NSURL) as Data?
    }

    func data(_ url: URL) async -> Data? {
        if let data = cached(url) { return data }
        if let task = running[url] { return await task.value }
        let task = Task<Data?, Never> {
            guard let (data, response) = try? await Self.session.data(from: url),
                  let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
                  !data.isEmpty else { return nil }
            return data
        }
        running[url] = task
        let data = await task.value
        running[url] = nil
        if let data { memory.setObject(data as NSData, forKey: url as NSURL, cost: data.count) }
        return data
    }

    /// Das erste der Formate, das sich lesen laesst - WebP ist kleiner als
    /// GIF; kann ImageIO es nicht, kommt das GIF.
    func animated(_ urls: [URL]) async -> (data: Data, url: URL)? {
        for url in urls {
            guard let data = await data(url) else { continue }
            if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
                return (data, url)
            }
        }
        return nil
    }

    func image(_ url: URL) async -> UIImage? {
        await data(url).flatMap(UIImage.init(data:))
    }
}

/// Ein GIF aus der Suche im Chat: wie ein Foto, ohne Blase, im
/// Seitenverhaeltnis des GIFs. Erst das Standbild (`stillUrl`), dann animiert
/// (`webpUrl`, sonst `gifUrl`).
struct GifMessageView: View {
    let gif: GifView
    var width: CGFloat = 220
    var placeholder: Color = Ink.track

    @State private var still: UIImage?
    @State private var animated: (data: Data, url: URL)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func height(for gif: GifView, width: CGFloat) -> CGFloat {
        min(max(width * gif.aspect, 110), 320)
    }

    var body: some View {
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let animated {
                    AnimatedImageView(data: animated.data, key: animated.url.absoluteString, animates: !reduceMotion)
                } else if let still {
                    Image(uiImage: still).resizable().scaledToFill()
                }
            }
            .frame(width: width, height: Self.height(for: gif, width: width))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: gif.gifUrl) {
                let media = KlipyMedia.shared
                let urls = [gif.webpUrl, gif.gifUrl].compactMap { $0.flatMap(URL.init(string:)) }
                if let cached = urls.lazy.compactMap({ url in media.cached(url).map { (data: $0, url: url) } }).first {
                    animated = cached
                    return
                }
                if let still = gif.stillUrl.flatMap(URL.init(string:)) {
                    self.still = await media.image(still)
                }
                animated = await media.animated(urls)
            }
            .accessibilityElement()
            .accessibilityLabel(gif.title.map { "GIF: \($0)" } ?? "GIF")
            .accessibilityIdentifier("gif-\(gif.slug)")
    }
}

/// Ein eigenes GIF (`kind: PHOTO`, `photoAnimated`): erst das Vorschaubild
/// (erstes Bild, JPEG), dann die Datei selbst, animiert.
struct AnimatedPhotoView: View {
    let id: String
    var placeholder: Color = Ink.track

    @State private var data: Data?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let data {
                AnimatedImageView(data: data, key: id, animates: !reduceMotion)
            } else {
                PhotoView(id: id, size: .thumb, placeholder: placeholder)
            }
        }
        .task(id: id) {
            data = await PhotoLoader.shared.data(id, size: .full)
        }
        .accessibilityElement()
        .accessibilityLabel("GIF")
    }
}
