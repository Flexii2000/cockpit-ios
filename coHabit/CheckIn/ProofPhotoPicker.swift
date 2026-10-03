import PhotosUI
import SwiftUI
import UIKit

/// Ein Beweisfoto im Blatt: gerade aufgenommen oder gewaehlt - oder beim
/// Bearbeiten eines Eintrags schon beim Dienst.
enum ProofPhoto: Identifiable, Equatable {
    case local(id: UUID, image: UIImage)
    case remote(String)

    init(_ image: UIImage) {
        self = .local(id: UUID(), image: image)
    }

    var id: String {
        switch self {
        case .local(let id, _): id.uuidString
        case .remote(let id): id
        }
    }

    /// Das Bild, das erst noch hoch muss.
    var image: UIImage? {
        if case .local(_, let image) = self { return image }
        return nil
    }

    static func == (lhs: ProofPhoto, rhs: ProofPhoto) -> Bool { lhs.id == rhs.id }
}

/// Die Beweisfotos eines Eintrags, bis zu vier (Vertrag §2.3a): Kamera-
/// Vorschau mit Ausloeser, Galerie (mehrere auf einmal) und Kamerawechsel;
/// nach dem ersten Foto eine umbrechende Reihe Vorschaubilder mit „×" und
/// einer „+"-Kachel fuer ein weiteres. Im Beweisfoto- und im Lauf-Blatt
/// steht das gewaehlte Foto gross darueber; beim Bearbeiten nur die Reihe.
///
/// Die Kamera laeuft nur, solange ihre Vorschau zu sehen ist.
struct ProofPhotoPicker: View {
    @Binding var photos: [ProofPhoto]
    let color: PaletteKey
    /// Das gewaehlte Foto gross zeigen (Eintragen) - beim Bearbeiten nicht.
    let showsSelection: Bool

    @State private var adding: Bool
    @State private var selected: String?
    @State private var camera = CameraController()
    @State private var cameraRunning = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var capturing = false
    /// Nur fuer `COCKPIT_TEST_PHOTO`: das wievielte erzeugte Bild.
    @State private var testShots = 0

    init(photos: Binding<[ProofPhoto]>, color: PaletteKey, showsSelection: Bool = true) {
        _photos = photos
        self.color = color
        self.showsSelection = showsSelection
        // Ein neuer Eintrag beginnt mit der Kamera, ein bestehender mit seinen Fotos.
        _adding = State(initialValue: showsSelection && photos.wrappedValue.isEmpty)
    }

    private var colors: PaletteColor { color.colors }
    private var isFull: Bool { photos.count >= PhotoList.maxCount }
    private var showsCamera: Bool { adding && !isFull }
    private var shown: ProofPhoto? { photos.first { $0.id == selected } ?? photos.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsCamera {
                cameraArea
            } else if showsSelection, let shown {
                large(shown)
            }
            if !photos.isEmpty || !showsSelection {
                thumbnails
            }
        }
        .task(id: showsCamera) {
            if showsCamera {
                cameraRunning = await camera.start()
            } else {
                camera.stop()
                cameraRunning = false
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                pickerItems = []
                add(images)
            }
        }
    }

    private func add(_ images: [UIImage]) {
        let room = PhotoList.maxCount - photos.count
        let added = images.prefix(max(0, room)).map(ProofPhoto.init)
        guard let last = added.last else { return }
        photos.append(contentsOf: added)
        selected = last.id
        adding = false
    }

    private func remove(_ photo: ProofPhoto) {
        photos.removeAll { $0.id == photo.id }
        if selected == photo.id { selected = nil }
        // Ohne Foto wieder die Kamera - wie zu Beginn.
        if photos.isEmpty && showsSelection { adding = true }
    }

    // MARK: - Gross

    private func large(_ photo: ProofPhoto) -> some View {
        // Fester Rahmen, Inhalt als overlay - ein Foto mit `scaledToFill`
        // machte das Blatt sonst breiter als den Bildschirm.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .overlay {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityIdentifier("chosenPhoto")
                } else if case .remote(let id) = photo {
                    PhotoView(id: id, size: .full, placeholder: colors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    // MARK: - Kamera

    private var cameraArea: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .overlay {
                    if cameraRunning {
                        CameraPreview(session: camera.session)
                    } else {
                        StripedPlaceholder(color: colors.accent, label: "Kamera-Vorschau")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            HStack {
                galleryButton
                Spacer()
                Button {
                    Task {
                        capturing = true
                        let image = await camera.capture()
                        capturing = false
                        if let image { add([image]) }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: 0x1C1B2E))
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                        .overlay { if capturing { ProgressView().tint(.white) } }
                }
                .disabled(!cameraRunning || capturing)
                .accessibilityLabel("Auslöser")
                .accessibilityIdentifier("shutter")
                Spacer()
                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 50, height: 50)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!cameraRunning)
                .opacity(cameraRunning ? 1 : 0.5)
                .accessibilityLabel("Kamera wechseln")
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var galleryButton: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_TEST_PHOTO"] == "1" {
            // Nur fuer UI-Tests ohne Galerie-Zugriff: ein erzeugtes Bild statt
            // der Mediathek. Steht hinter dem Schalter, nicht nur hinter DEBUG.
            Button {
                add([Self.testImage(testShots)])
                testShots += 1
            } label: { GalleryLabel() }
                .accessibilityLabel("Galerie")
                .accessibilityIdentifier("photoGallery")
        } else {
            picker
        }
        #else
        picker
        #endif
    }

    /// Mehrere auf einmal, bis die vier voll sind - in der gewaehlten Reihenfolge.
    private var picker: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, PhotoList.maxCount - photos.count),
                     selectionBehavior: .ordered, matching: .images) { GalleryLabel() }
            .accessibilityLabel("Galerie")
            .accessibilityIdentifier("photoGallery")
    }

    #if DEBUG
    /// Je Platz eine andere Farbe - sonst saehe man im Karussell nicht, dass gewischt wurde.
    static func testImage(_ index: Int) -> UIImage {
        let colors: [UIColor] = [
            UIColor(red: 0.95, green: 0.63, blue: 0.48, alpha: 1),
            UIColor(red: 0.47, green: 0.78, blue: 0.66, alpha: 1),
            UIColor(red: 0.55, green: 0.60, blue: 0.93, alpha: 1),
            UIColor(red: 0.96, green: 0.80, blue: 0.38, alpha: 1),
        ]
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            colors[index % colors.count].setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.35).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 700, y: -150, width: 700, height: 700))
        }
    }
    #endif

    // MARK: - Reihe

    private var thumbnails: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                thumbnail(photo, index: index)
            }
            if !isFull {
                Button {
                    adding = true
                } label: {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(showsCamera ? Ink.accentSoft : Color.clear)
                        .strokeBorder(Ink.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Ink.ink)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weiteres Foto")
                .accessibilityIdentifier("addPhoto")
            }
        }
    }

    private func thumbnail(_ photo: ProofPhoto, index: Int) -> some View {
        let highlighted = showsSelection && !showsCamera && shown?.id == photo.id
        return ZStack(alignment: .topTrailing) {
            Button {
                selected = photo.id
                adding = false
            } label: {
                Color.clear
                    .frame(width: 72, height: 72)
                    .overlay {
                        if let image = photo.image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if case .remote(let id) = photo {
                            PhotoView(id: id, size: .thumb, placeholder: colors.surface)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Ink.ink, lineWidth: highlighted ? 2.5 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Foto \(index + 1)")
            .accessibilityIdentifier("photoThumb-\(index)")
            Button {
                remove(photo)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(hex: 0x1C1B2E).opacity(0.85), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Foto \(index + 1) entfernen")
            .accessibilityIdentifier("removePhoto-\(index)")
        }
    }
}

/// Der Galerie-Knopf in der Kamera-Vorschau.
private struct GalleryLabel: View {
    var body: some View {
        Image(systemName: "photo")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Ink.ink)
            .frame(width: 50, height: 50)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
