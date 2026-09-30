@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Die Kamera im Beweisfoto-Blatt (Entwurf S. 15): Vorschau im Blatt statt
/// eines Vollbild-Pickers, mit Ausloeser und Kamerawechsel.
///
/// Die Sitzung laeuft auf einer eigenen Warteschlange - `startRunning` blockiert.
final class CameraController: NSObject, @unchecked Sendable {

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.fherrmann.cohabit.camera")
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var pending: CheckedContinuation<UIImage?, Never>?

    /// Im Simulator gibt es keine Kamera - dann bleibt es bei der Galerie.
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    /// Fragt nach der Erlaubnis und startet. `false`: keine Kamera oder kein Ja.
    func start() async -> Bool {
        guard Self.isAvailable else { return false }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { return false }
        return await withCheckedContinuation { continuation in
            queue.async {
                self.configure()
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.input != nil)
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func switchCamera() {
        queue.async {
            self.position = self.position == .back ? .front : .back
            self.configure()
        }
    }

    func capture() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.input != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                self.pending = continuation
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        input = nil
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let newInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        // UIImage aus den Dateidaten traegt die Ausrichtung; aufrecht
        // gezeichnet wird beim Kodieren (PhotoEncoding).
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        queue.async {
            self.pending?.resume(returning: image)
            self.pending = nil
        }
    }
}

/// Die Vorschau als SwiftUI-Ansicht.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
