import Foundation
import UserNotifications

/// Haengt das Bild an eine Benachrichtigung von coHabit (Vertrag §2.7a):
/// Beweisfoto, Foto oder eigenes GIF im Chat vom Dienst (mit dem Token aus
/// dem gemeinsamen Schluesselbund), ein GIF aus der Suche direkt von KLIPY.
/// Ein GIF bleibt animiert.
///
/// iOS startet die Erweiterung nur bei `mutable-content: 1` und gibt ihr
/// rund 30 Sekunden. Reicht die Zeit nicht oder schlaegt etwas fehl, kommt
/// die Meldung, wie sie war - ohne Bild, nie gar nicht.
///
/// Uebersetzt bewusst nur diese Datei, `NotificationImage`, `ImageFormat`,
/// `CohabitToken`, `Keychain` und `Backend` (project.yml): `CohabitAPI` zoege
/// Postausgang, Offline-Stand und Oberflaechen-Zustand mit hinein, und eine
/// Erweiterung hat wenig Speicher.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {

    // Geschuetzt durch `lock`: der Abschluss kommt aus der URLSession-Schlange,
    // der Ablauf der Zeit von iOS - beide duerfen nur einmal zustellen.
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var task: URLSessionDataTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        guard let source = NotificationImage.source(from: request.content.userInfo),
              let imageRequest = NotificationImage.request(for: source, base: NotificationImage.base(),
                                                          token: CohabitToken.load()) else {
            contentHandler(content)
            return
        }
        lock.withLock {
            self.contentHandler = contentHandler
            self.content = content
        }
        let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(source: source), delegateQueue: nil)
        let task = session.dataTask(with: imageRequest) { [weak self] data, response, _ in
            self?.finish(data: data, response: response)
            session.finishTasksAndInvalidate()
        }
        lock.withLock { self.task = task }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        let task = lock.withLock { self.task }
        task?.cancel()
        deliver(attachment: nil)
    }

    private func finish(data: Data?, response: URLResponse?) {
        deliver(attachment: Self.attachment(data: data, response: response))
    }

    /// Die Anlage aus der Antwort - `nil` bei Fehlerstatus, zu gross, kein Bild.
    private static func attachment(data: Data?, response: URLResponse?) -> UNNotificationAttachment? {
        guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let ext = NotificationImage.fileExtension(contentType: http.value(forHTTPHeaderField: "Content-Type"),
                                                        data: data) else { return nil }
        // iOS verschiebt die Datei beim Anlegen der Anlage in seinen eigenen Speicher.
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + ext)
        guard (try? data.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "image", url: file)
    }

    /// Stellt genau einmal zu - wer zuerst kommt, Laden oder Ablauf der Zeit.
    private func deliver(attachment: UNNotificationAttachment?) {
        let pending: (((UNNotificationContent) -> Void), UNMutableNotificationContent)? = lock.withLock {
            defer {
                contentHandler = nil
                content = nil
                task = nil
            }
            guard let contentHandler, let content else { return nil }
            return (contentHandler, content)
        }
        guard let (contentHandler, content) = pending else { return }
        if let attachment { content.attachments = [attachment] }
        contentHandler(content)
    }
}

/// Weiterleitungen: beim Foto keine (der Token ginge mit), beim GIF nur
/// zwischen KLIPYs Medien-Hosts.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let source: NotificationImage.Source

    init(source: NotificationImage.Source) {
        self.source = source
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        NotificationImage.allowsRedirect(for: source, to: request.url) ? request : nil
    }
}
