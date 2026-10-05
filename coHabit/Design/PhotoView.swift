import SwiftUI
import UIKit

/// Laedt Fotos des Dienstes - mit Token, deshalb kein `AsyncImage`.
///
/// Fotos aendern sich nie (der Dienst liefert sie `immutable`, Vertrag §3.8),
/// also bleibt jedes einmal geholte auf der Platte liegen: ohne Netz ist der
/// Chat dann trotzdem bebildert, und beim Scrollen wird nichts doppelt geholt.
@MainActor
final class PhotoLoader {

    enum Size: String { case thumb, full }

    static let shared = PhotoLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var running: [String: Task<UIImage?, Never>] = [:]
    private var loading: [String: Task<Data?, Never>] = [:]

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "CohabitPhotos")
    }

    func cached(_ id: String, size: Size) -> UIImage? {
        memory.object(forKey: key(id, size) as NSString)
    }

    func image(_ id: String, size: Size) async -> UIImage? {
        let key = key(id, size)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = running[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = await self.data(id, size: size) else { return nil }
            return UIImage(data: data)
        }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Die Datei, wie der Dienst sie liefert - fuer ein eigenes GIF
    /// (`size=full` ist dann `image/gif`, Vertrag §2.7a), das als `UIImage`
    /// nur sein erstes Bild zeigte. Liegt nach dem ersten Laden auf der Platte.
    func data(_ id: String, size: Size) async -> Data? {
        let key = key(id, size)
        let file = Self.directory.appending(path: key + ".jpg")
        if let data = try? Data(contentsOf: file) { return data }
        if let task = loading[key] { return await task.value }
        let task = Task<Data?, Never> {
            guard let data = try? await CohabitAPI().data("/photos/\(id)", query: [
                URLQueryItem(name: "size", value: size.rawValue),
            ]), !data.isEmpty else { return nil }
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        }
        loading[key] = task
        let data = await task.value
        loading[key] = nil
        return data
    }

    /// Ein gerade selbst hochgeladenes Foto sofort zeigen, ohne es erst
    /// wieder herunterzuladen.
    func remember(_ image: UIImage, id: String) {
        memory.setObject(image, forKey: key(id, .full) as NSString)
        memory.setObject(image, forKey: key(id, .thumb) as NSString)
    }

    /// Dasselbe fuer ein eigenes GIF: die Datei, wie sie hochging, ist die,
    /// die der Dienst als `full` liefert.
    func remember(fullData data: Data, id: String) {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.directory.appending(path: key(id, .full) + ".jpg"), options: .atomic)
        if let image = UIImage(data: data) { remember(image, id: id) }
    }

    /// Beim Abmelden.
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.directory)
    }

    private func key(_ id: String, _ size: Size) -> String { "\(id)-\(size.rawValue)" }
}

/// Ein Foto des Dienstes, fuellend beschnitten.
struct PhotoView: View {
    let id: String
    var size: PhotoLoader.Size = .full
    var placeholder: Color = Ink.track

    @State private var image: UIImage?

    var body: some View {
        // Das Bild liegt als overlay: `scaledToFill` meldet sonst die Groesse
        // des gefuellten Bildes und macht den Rahmen breiter als vorgesehen.
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
        .task(id: id + size.rawValue) {
            if let cached = PhotoLoader.shared.cached(id, size: size) {
                image = cached
                return
            }
            image = await PhotoLoader.shared.image(id, size: size)
        }
        .accessibilityLabel("Foto")
    }
}

/// Die Beweisfotos eines Eintrags in voller Breite (Vertrag §2.3a): eins wie
/// bisher, mehrere als wischbares Karussell mit Punkten darunter.
struct PhotoCarousel: View {
    let ids: [String]
    var height: CGFloat = 220
    var cornerRadius: CGFloat = 18
    var placeholder: Color = Ink.track

    @State private var page = 0

    var body: some View {
        if ids.count == 1, let id = ids.first {
            PhotoView(id: id, size: .full, placeholder: placeholder)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if !ids.isEmpty {
            VStack(spacing: 8) {
                TabView(selection: $page) {
                    ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                        PhotoView(id: id, size: .full, placeholder: placeholder)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .accessibilityIdentifier("photoCarousel")
                PageDots(count: ids.count, current: min(page, ids.count - 1))
            }
            // Ein bearbeiteter Eintrag hat womoeglich weniger Fotos als vorher.
            .onChange(of: ids) { _, new in page = min(page, max(0, new.count - 1)) }
        }
    }
}

/// Die Punkte unter dem Karussell - der aktuelle in Tinte.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Ink.ink : Ink.ink.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Foto \(current + 1) von \(count)")
        .accessibilityIdentifier("photoDots")
    }
}
