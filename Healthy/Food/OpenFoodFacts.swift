import Foundation

/// Ein Produkt aus Open Food Facts - nur das, was ein Gericht im
/// Kalorienzaehler braucht. Werte je 100 g; was dort fehlt, bleibt `nil`,
/// damit im Blatt ein leeres Feld steht und keine Null, die wie ein
/// abgelesener Wert aussieht.
struct ScannedProduct: Equatable, Sendable {
    let name: String
    let brand: String?
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    /// Eine Portion in Gramm, wenn die Datenbank eine kennt - aus
    /// `serving_size`, sonst aus der Packungsgroesse `quantity`.
    let servingG: Double?

    /// „Marzipan (Ritter Sport)" - so heisst das Gericht dann in der
    /// Merkliste, und daran wird es beim naechsten Scan wiedererkannt.
    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return name.isEmpty ? brand : "\(name) (\(brand))"
    }
}

/// Was der Scanner ins Eintrag-Blatt traegt: das Produkt - oder nur den
/// Code, wenn Open Food Facts ihn nicht kennt.
struct ScanResult: Identifiable, Equatable, Sendable {
    let code: String
    let product: ScannedProduct?
    var id: String { code }
}

enum OpenFoodFactsError: LocalizedError {
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .http(let code): "Open Food Facts hat mit \(code) geantwortet."
        case .unreadable:     "Die Antwort von Open Food Facts war nicht zu lesen."
        }
    }
}

/// Open Food Facts, direkt aus der App und nicht ueber den Kalorienzaehler
/// (docs/ENTSCHEIDUNGEN.md, 2026-09-21). Endpunkt und Felder: docs/BACKENDS.md.
struct OpenFoodFactsAPI: Sendable {

    /// Open Food Facts bittet um einen sprechenden User-Agent. Mehr geht
    /// nicht mit: keine Kennung, keine Adresse, kein Cookie.
    static let userAgent = "Cockpit-iOS/0.2 (private, non-commercial)"
    static let fields = "product_name,brands,quantity,serving_size,nutriments"

    var timeout: TimeInterval = 15

    /// `nil` heisst: nicht in der Datenbank.
    func product(code: String) async throws -> ScannedProduct? {
        var request = URLRequest(url: Self.url(for: code))
        request.timeoutInterval = timeout
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Die Cookies der eigenen Dienste gelten nur fuer fherrmann.com -
        // hier trotzdem ausdruecklich keine.
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Unbekannter Code: 404, aber mit JSON-Rumpf (`status: 0`) - eine
        // Antwort, kein Fehler.
        guard (200..<300).contains(status) || status == 404 else {
            throw OpenFoodFactsError.http(status)
        }
        return try OpenFoodFactsParser.parse(data)
    }

    static func url(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(code).json"
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components.url!
    }
}

/// Liest die Antwort von `/api/v2/product/<code>.json`. Ohne Netz, damit
/// sich echte Antworten als Auszug pruefen lassen (Tests/OpenFoodFactsTests).
enum OpenFoodFactsParser {

    static func parse(_ data: Data) throws -> ScannedProduct? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenFoodFactsError.unreadable
        }
        // `status` 0 heisst „product not found" - und ein Rumpf ohne `product`
        // ebenfalls, was immer `status` sagt.
        if let status = number(root["status"]), status == 0 { return nil }
        guard let product = root["product"] as? [String: Any] else { return nil }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        // Open Food Facts rechnet die Energie stets nach kJ um (`energy_100g`);
        // kcal steht nur da, wenn es jemand eingetragen hat.
        let kcal = number(nutriments["energy-kcal_100g"])
            ?? number(nutriments["energy_100g"]).map { $0 / 4.184 }
        return ScannedProduct(
            name: text(product["product_name"]),
            brand: firstBrand(text(product["brands"])),
            kcal: kcal,
            proteinG: number(nutriments["proteins_100g"]),
            carbsG: number(nutriments["carbohydrates_100g"]),
            fatG: number(nutriments["fat_100g"]),
            servingG: grams(in: text(product["serving_size"]))
                ?? grams(in: text(product["quantity"])))
    }

    /// Zahlen kommen mal als Zahl, mal als String („12.5") - je nachdem, wie
    /// der Eintrag entstanden ist.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "."))
        default:
            nil
        }
    }

    /// `brands` ist eine Liste („Alnatura, Bio") - der erste Name reicht.
    static func firstBrand(_ brands: String) -> String? {
        let first = brands.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? nil : first
    }

    /// Die erste Grammzahl im Text: „30 g", „250ml", „1 Cube (6.52 g)" und
    /// „6 x 125 g" ergeben 30, 250, 6,52 und 125. Nur g und ml: eine Packung
    /// „1 l" oder „1,5 kg" ist keine Portion, und was in Stueck oder Scheiben
    /// angegeben ist, laesst sich nicht in Gramm eintragen.
    static func grams(in text: String) -> Double? {
        let pattern = #/(\d+(?:[.,]\d+)?)\s*(?:g|ml)\b/#.ignoresCase()
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return Double(match.1.replacingOccurrences(of: ",", with: "."))
    }

    private static func text(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
