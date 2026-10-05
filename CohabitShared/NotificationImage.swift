import Foundation

/// Das Bild zu einer Benachrichtigung (Vertrag §2.7a, §4): was die
/// Notification Service Extension `coHabitNotifications` laedt und wie sie es
/// anhaengt - ohne UserNotifications, damit es sich pruefen laesst
/// (`CohabitTests`).
///
/// Die Datenfelder der Meldung kommen vom Dienst, aber die Erweiterung laedt
/// mit dem Token der Person - deshalb geht ein Foto nur an den eigenen Dienst
/// und ein GIF nur an KLIPYs Medien-Hosts, nie an eine beliebige Adresse.
enum NotificationImage {

    enum Source: Equatable, Sendable {
        /// Beweisfoto (bei mehreren das erste), Foto oder eigenes GIF im Chat:
        /// `GET /photos/{id}?size=full` mit Bearer.
        case photo(id: String)
        /// Ein GIF aus der Suche (`imageUrl` = `gifUrl`): direkt von KLIPY,
        /// ohne Token.
        case klipy(URL)
    }

    /// iOS nimmt Bilder als Anlage bis 10 MB.
    static let maxBytes = 10 * 1024 * 1024

    /// Wohin die Erweiterung ein Foto fragt: der Dienst wie in der App.
    static func base(groupDefaults: UserDefaults? = UserDefaults(suiteName: "group.com.fherrmann.cohabit")) -> URL {
        #if DEBUG
        if let raw = groupDefaults?.string(forKey: debugBaseKey), let url = URL(string: raw) { return url }
        #endif
        return Backend.cohabit.url
    }

    #if DEBUG
    /// Nur im Simulator gesetzt: die App biegt sich mit `COCKPIT_URL_COHABIT`
    /// auf einen lokalen Dienst um, die Erweiterung bekommt aber keine
    /// Umgebungsvariablen - die Adresse geht ueber die App-Gruppe mit. Ohne
    /// Schalter (auf dem Geraet immer) wird sie geloescht.
    static let debugBaseKey = "debug.cohabitBaseURL"

    static func handOverDebugBase(to groupDefaults: UserDefaults) {
        if let override = ProcessInfo.processInfo.environment["COCKPIT_URL_COHABIT"], URL(string: override) != nil {
            groupDefaults.set(override, forKey: debugBaseKey)
        } else {
            groupDefaults.removeObject(forKey: debugBaseKey)
        }
    }
    #endif

    /// Aus den Datenfeldern: `photoId` geht vor `imageUrl`. Ohne passendes
    /// Feld keine Quelle - dann kommt die Meldung ohne Bild.
    static func source(from userInfo: [AnyHashable: Any]) -> Source? {
        if let id = userInfo["photoId"] as? String, isPhotoId(id) {
            return .photo(id: id)
        }
        if let raw = userInfo["imageUrl"] as? String, let url = URL(string: raw), isKlipyMedia(url) {
            return .klipy(url)
        }
        return nil
    }

    /// Eine Kennung, die als ein Pfadstueck taugt - kein `/`, kein `..`.
    static func isPhotoId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128
            && id.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
            }
    }

    /// Nur `https://static.klipy.com/…`, `static1.klipy.com`, `static2.…` -
    /// wie der Dienst beim Senden prueft (`^https://static[0-9]*\.klipy\.com/`).
    static func isKlipyMedia(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host()?.lowercased(), host.hasSuffix(".klipy.com") else { return false }
        let label = host.dropLast(".klipy.com".count)
        guard label.hasPrefix("static") else { return false }
        return label.dropFirst("static".count).unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    /// Die Anfrage: das Foto mit Bearer an den Dienst, das GIF ohne alles an
    /// KLIPY. Ohne Token (abgemeldet, Geraet seit dem Neustart nie entsperrt)
    /// gibt es fuer ein Foto keine.
    static func request(for source: Source, base: URL, token: String?, timeout: TimeInterval = 20) -> URLRequest? {
        var request: URLRequest
        switch source {
        case .photo(let id):
            guard let token, !token.isEmpty else { return nil }
            var components = URLComponents(url: base.appending(path: "photos").appending(path: id),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "size", value: "full")]
            guard let url = components.url else { return nil }
            request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .klipy(let url):
            request = URLRequest(url: url)
        }
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// Ob eine Weiterleitung mitgehen darf: beim Foto nie (der Token ginge
    /// mit), beim GIF nur zu einem anderen Medien-Host von KLIPY.
    static func allowsRedirect(for source: Source, to url: URL?) -> Bool {
        guard case .klipy = source, let url else { return false }
        return isKlipyMedia(url)
    }

    /// Die Endung der Anlage - iOS erkennt das Bild nur daran. Erst am
    /// Dateianfang, dann am `Content-Type`; JPEG, PNG und GIF (bleibt
    /// animiert). Etwas anderes (WebP, eine Fehlerseite) gibt keine Anlage.
    static func fileExtension(contentType: String?, data: Data) -> String? {
        guard !data.isEmpty, data.count <= maxBytes,
              let format = ImageFormat.sniff(data) ?? ImageFormat.from(contentType: contentType) else { return nil }
        switch format {
        case .gif, .jpeg, .png: return format.fileExtension
        case .webp: return nil
        }
    }
}
