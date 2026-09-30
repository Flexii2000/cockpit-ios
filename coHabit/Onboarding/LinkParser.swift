import Foundation

/// Was ein Link in der App bewirkt (Vertrag §4 und §5.4).
enum DeepLink: Equatable, Sendable {
    case today, timeline, new, stats, profile, friends
    case cohabit(String)
    case chat(String)
    case checkIn(String)
    case invitation(String)
    case join(String)
    /// App-Link von coHabit (`/cohabit/setup?token=…`).
    case setup(token: String)
    /// Setup-Link von Healthy (`food.fherrmann.com/setup?token=…`) - der
    /// Token gilt bei coHabit genauso (Vertrag §1.2).
    case healthySetup(token: String)

    /// Ob der Link einen Zugang mitbringt.
    var token: String? {
        switch self {
        case .setup(let token), .healthySetup(let token): token
        default: nil
        }
    }
}

/// Erkennt Links - auch mitten in einem kopierten Text („Hier ist mein Link:
/// https://…"), so wie ihn WhatsApp oder Mail weiterreichen.
enum LinkParser {

    static func parse(_ url: URL) -> DeepLink? {
        switch url.scheme?.lowercased() {
        case "cohabit": return parseApp(url)
        case "https", "http": return parseWeb(url)
        default: return nil
        }
    }

    /// Der erste erkennbare Link im Text.
    static func find(in text: String) -> DeepLink? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"“”„«»'"))
        for raw in text.components(separatedBy: separators) where !raw.isEmpty {
            var candidate = raw.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,;:!?"))
            // „fherrmann.com/cohabit/join/…" ohne https - so kuerzen es manche Messenger.
            if !candidate.contains("://"), candidate.lowercased().contains("fherrmann.com/") {
                candidate = "https://" + candidate
            }
            if let url = URL(string: candidate), let link = parse(url) {
                return link
            }
        }
        return nil
    }

    // MARK: - cohabit://…

    private static func parseApp(_ url: URL) -> DeepLink? {
        // cohabit://cohabit/abc/chat - der erste Teil steht im Host.
        let parts = [url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }
        let segments = parts.filter { !$0.isEmpty }
        guard let first = segments.first?.lowercased() else { return nil }
        switch first {
        case "today": return .today
        case "timeline": return .timeline
        case "new": return .new
        case "stats": return .stats
        case "profile": return .profile
        case "friends": return .friends
        case "cohabit":
            guard segments.count >= 2 else { return nil }
            let id = segments[1]
            switch segments.count > 2 ? segments[2].lowercased() : "" {
            case "chat": return .chat(id)
            case "checkin": return .checkIn(id)
            default: return .cohabit(id)
            }
        case "invitation":
            return segments.count >= 2 ? .invitation(segments[1]) : nil
        case "join":
            return segments.count >= 2 ? .join(segments[1]) : nil
        case "setup":
            return token(in: url).map { .setup(token: $0) }
        default:
            return nil
        }
    }

    // MARK: - https://…

    private static func parseWeb(_ url: URL) -> DeepLink? {
        let host = (url.host() ?? "").lowercased()
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // Healthy: food.fherrmann.com/setup?token=… (der Weight Tracker stellt
        // mit einem persoenlichen Token denselben aus).
        if (host.hasPrefix("food.") || host.hasPrefix("weight.")), segments == ["setup"] {
            return token(in: url).map { .healthySetup(token: $0) }
        }

        // Alles unter /cohabit/ - der Rechner ist egal: ein lokal gestarteter
        // Dienst stellt Links auf seine eigene Adresse aus, und der Token geht
        // ohnehin nur an die eingestellte API.
        guard segments.first?.lowercased() == "cohabit" else { return nil }
        let rest = Array(segments.dropFirst())
        guard let first = rest.first?.lowercased() else { return .today }
        switch first {
        case "setup": return token(in: url).map { .setup(token: $0) }
        case "join": return rest.count >= 2 ? .join(rest[1]) : nil
        case "timeline": return .timeline
        case "neu": return .new
        case "statistik": return .stats
        case "profil": return .profile
        case "freunde": return .friends
        case "c":
            guard rest.count >= 2 else { return nil }
            return rest.count >= 3 && rest[2].lowercased() == "chat" ? .chat(rest[1]) : .cohabit(rest[1])
        default: return nil
        }
    }

    private static func token(in url: URL) -> String? {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "token" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
