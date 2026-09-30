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
            let file = Self.directory.appending(path: key + ".jpg")
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image
            }
            guard let data = try? await CohabitAPI().data("/photos/\(id)", query: [
                URLQueryItem(name: "size", value: size.rawValue),
            ]), let image = UIImage(data: data) else { return nil }
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return image
        }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Ein gerade selbst hochgeladenes Foto sofort zeigen, ohne es erst
    /// wieder herunterzuladen.
    func remember(_ image: UIImage, id: String) {
        memory.setObject(image, forKey: key(id, .full) as NSString)
        memory.setObject(image, forKey: key(id, .thumb) as NSString)
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
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(placeholder)
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
