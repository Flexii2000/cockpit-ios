import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Der Scanner: der erste Code, den die Kamera erkennt, geht zurueck, und das
/// Blatt schliesst sich. Nachgeschlagen wird erst danach, im Essen-Tab - ein
/// zweites Blatt kann erst aufgehen, wenn dieses zu ist.
struct BarcodeScannerSheet: View {

    /// Bekommt die GTIN (siehe `ProductCode`), nicht den rohen Inhalt.
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state = ScannerState.checking
    @State private var note: String?
    @State private var delivered = false

    private enum ScannerState: Equatable {
        case checking
        case ready
        case unavailable(String)
    }

    #if DEBUG
    /// `COCKPIT_SCAN=<code>`: das Blatt liefert diesen Code sofort, ohne
    /// Kamera - im Simulator gibt es keine, und der Ablauf dahinter soll sich
    /// trotzdem ansehen lassen.
    static var debugCode: String? {
        guard let code = ProcessInfo.processInfo.environment["COCKPIT_SCAN"],
              !code.isEmpty else { return nil }
        return code
    }
    #endif

    var body: some View {
        NavigationStack {
            content
                .overlay(alignment: .bottom) {
                    if let note {
                        Text(note)
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 32)
                    }
                }
                .navigationTitle("Scannen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
                .task { await prepare() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .checking:
            Color.clear
        case .ready:
            DataScannerView(onPayload: handle)
                .ignoresSafeArea()
        case .unavailable(let message):
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    private func prepare() async {
        #if DEBUG
        if let code = Self.debugCode {
            handle(payload: code)
            return
        }
        #endif
        // Simulator und alte Geraete: kein Scanner. Lieber ein Satz als ein
        // Absturz in `startScanning`.
        guard DataScannerViewController.isSupported else {
            state = .unavailable("Kein Scanner auf diesem Gerät.")
            return
        }
        // Die Erlaubnis selbst erfragen, bevor der Scanner steht:
        // `isAvailable` ist erst wahr, wenn sie erteilt ist.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .unavailable("Kein Zugriff auf die Kamera.")
                return
            }
        default:
            state = .unavailable("Kein Zugriff auf die Kamera.")
            return
        }
        guard DataScannerViewController.isAvailable else {
            state = .unavailable("Kamera nicht verfügbar.")
            return
        }
        state = .ready
    }

    private func handle(payload: String) {
        guard !delivered else { return }
        guard let code = ProductCode.gtin(from: payload) else {
            // Ein QR-Code mit einer Webseite darauf: weiter scannen, mit
            // einem Wort dazu.
            note = "Kein Produktcode."
            return
        }
        delivered = true
        onScan(code)
        dismiss()
    }
}

/// `DataScannerViewController` in SwiftUI. Nur Strichcodes, kein Text.
private struct DataScannerView: UIViewControllerRepresentable {

    let onPayload: (String) -> Void

    /// EAN/UPC sind die Regel im Supermarkt; QR und DataMatrix tragen
    /// GS1-Links, Code 128 und die DataBar-Familie stehen auf Frischware.
    private static let symbologies: [VNBarcodeSymbology] = [
        .ean8, .ean13, .upce, .code128, .qr,
        .itf14, .dataMatrix, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
    ]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // Erst hier starten, nicht in `make…`: dort haengt der Controller noch
        // an keiner Hierarchie. Ein Fehlschlag (Kamera belegt) bleibt stumm -
        // die Erlaubnis ist vorher geprueft, mehr laesst sich hier nicht tun.
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController,
                                          coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Der erste Code mit Inhalt reicht - vor der Kamera liegt genau
            // eine Packung.
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    onPayload(payload)
                    return
                }
            }
        }
    }
}
