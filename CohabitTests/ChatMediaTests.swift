import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import coHabit

/// GIFs im Chat und Emoji-Reaktionen (Vertrag §2.7a, seit 2026-10-05):
/// was der Dienst schickt, was die App sendet, die Suche bei KLIPY und eigene
/// GIF-Dateien, die unveraendert hochgehen - auch aus dem Postausgang.
@MainActor
final class ChatMediaTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Ein GIF mit zwei Bildern, mit ImageIO erzeugt - so sieht ein eigenes
    /// GIF aus der Galerie aus.
    nonisolated static func animatedGif() -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)!
        for color in [UIColor.red, UIColor.blue] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            CGImageDestinationAddImage(destination, image.cgImage!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    nonisolated static let gifView = """
        {"provider":"KLIPY","slug":"hello-hi-662","title":"Hello","width":498,"height":374,
         "gifUrl":"https://static.klipy.com/ii/a/b/c.gif","webpUrl":"https://static.klipy.com/ii/a/b/c.webp",
         "mp4Url":null,"stillUrl":"https://static1.klipy.com/ii/a/b/c.jpg"}
        """

    // MARK: - Lesen

    func testGifMessageAndAnimatedPhotoDecode() throws {
        let gif = try decode(Message.self, """
            {"id":"m7","cohabitId":"c-3f2a","kind":"GIF","author":\(Fixtures.lena),"mine":false,
             "createdAt":"2026-10-05T07:00:00Z","text":null,"photoId":null,"photoAnimated":false,
             "gif":\(Self.gifView),"checkin":null,"systemText":null,"reactionTarget":"message:m7",
             "reactions":[{"reaction":"🔥","label":"🔥","count":2,"mine":true,"people":[\(Fixtures.lena),\(Fixtures.felix)]}],
             "deleted":false}
            """)
        XCTAssertEqual(gif.kind, .gif)
        XCTAssertEqual(gif.gif?.slug, "hello-hi-662")
        XCTAssertEqual(gif.gif?.provider, "KLIPY")
        XCTAssertNil(gif.gif?.mp4Url)
        XCTAssertEqual(gif.gif?.aspect ?? 0, 374.0 / 498.0, accuracy: 0.0001)
        XCTAssertFalse(gif.isAnimatedPhoto)
        XCTAssertEqual(gif.reactions.first?.reaction, "🔥")
        XCTAssertEqual(gif.reactions.first?.people.map(\.id), ["lena", "felix"])
        // Reaktionen bleiben beim Ersetzen erhalten - auch das GIF.
        XCTAssertEqual(gif.with(reactions: []).gif, gif.gif)

        let own = try decode(Message.self, """
            {"id":"m8","cohabitId":"c-3f2a","kind":"PHOTO","author":\(Fixtures.felix),"mine":true,
             "createdAt":"2026-10-05T07:01:00Z","text":"Na?","photoId":"p-gif","photoAnimated":true,
             "gif":null,"checkin":null,"systemText":null,"reactionTarget":"message:m8","reactions":[],"deleted":false}
            """)
        XCTAssertEqual(own.kind, .photo)
        XCTAssertTrue(own.isAnimatedPhoto)
        XCTAssertTrue(own.with(reactions: []).isAnimatedPhoto)

        // Ein aelterer Dienst kennt beide Felder nicht.
        let older = try decode(MessagesPage.self, Fixtures.messages).messages[1]
        XCTAssertNil(older.gif)
        XCTAssertFalse(older.isAnimatedPhoto)
    }

    func testReactionViewReadsEmojisPeopleAndTheOldNames() throws {
        let new = try decode(ReactionView.self, #"{"reaction":"❤️","label":"❤️","count":1,"mine":false,"people":[\#(Fixtures.lena)]}"#)
        XCTAssertEqual(new.reaction, "❤️")
        XCTAssertEqual(new.people.first?.displayName, "Lena")
        let old = try decode(ReactionView.self, #"{"reaction":"STARK","label":"Stark","count":2,"mine":true}"#)
        XCTAssertEqual(old.reaction, "💪")
        XCTAssertEqual(old.people, [])
        XCTAssertTrue(old.mine)
        let unknownOld = try decode(ReactionView.self, #"{"reaction":"HAHA","count":1}"#)
        XCTAssertEqual(unknownOld.reaction, "😂")
        XCTAssertEqual(unknownOld.label, "😂")
        XCTAssertFalse(unknownOld.mine)
    }

    func testGifConfig() throws {
        let on = try decode(GifConfig.self, #"{"enabled":true,"apiKey":"k","customerId":"c-1","locale":"de","contentFilter":"medium"}"#)
        XCTAssertTrue(on.isUsable)
        XCTAssertNotNil(KlipyClient(config: on))
        let off = try decode(GifConfig.self, #"{"enabled":false}"#)
        XCTAssertFalse(off.isUsable)
        XCTAssertNil(KlipyClient(config: off), "ohne Schluessel kein GIF-Knopf")
        XCTAssertNil(KlipyClient(config: nil), "ein aelterer Dienst ohne /gifs/config")
        XCTAssertNil(KlipyClient(config: GifConfig(enabled: true, apiKey: "")))
    }

    // MARK: - Senden

    func testMessageRequestCarriesTheGifWithAllKeys() throws {
        let gif = GifInput(slug: "hello-hi-662", title: "Hello", width: 498, height: 498,
                           gifUrl: "https://static.klipy.com/x.gif", webpUrl: nil, mp4Url: "https://static.klipy.com/x.mp4",
                           stillUrl: nil)
        let body = try object(MessageRequest(id: "m1", text: nil, gif: gif))
        XCTAssertEqual(body["id"] as? String, "m1")
        XCTAssertTrue(body["text"] is NSNull)
        XCTAssertTrue(body["photoId"] is NSNull)
        let sent = try XCTUnwrap(body["gif"] as? [String: Any])
        XCTAssertEqual(sent["slug"] as? String, "hello-hi-662")
        XCTAssertEqual(sent["width"] as? Int, 498)
        XCTAssertEqual(sent["gifUrl"] as? String, "https://static.klipy.com/x.gif")
        XCTAssertTrue(sent["webpUrl"] is NSNull, "auch leere Schluessel stehen da")
        XCTAssertTrue(sent["stillUrl"] is NSNull)
        XCTAssertEqual(Set(sent.keys), ["slug", "title", "width", "height", "gifUrl", "webpUrl", "mp4Url", "stillUrl"])

        let plain = try object(MessageRequest(id: "m2", text: "Hallo"))
        XCTAssertTrue(plain["gif"] is NSNull)
        // Ein Auftrag im Postausgang aus der Zeit vor den GIFs.
        let old = try APIClient.decoder().decode(MessageRequest.self, from: Data(#"{"id":"m3","text":"Hi","photoId":null}"#.utf8))
        XCTAssertNil(old.gif)
    }

    // MARK: - KLIPY

    nonisolated static let klipyPage = """
        {"result":true,"data":{"data":[
          {"id":8041071659142944,"slug":"hello-hi-662","title":"Hello","type":"gif",
           "blur_preview":"data:image/jpeg;base64,AAEC",
           "file":{"hd":{"gif":{"url":"https://static.klipy.com/hd.gif","width":640,"height":480,"size":4000000}},
                   "md":{"gif":{"url":"https://static.klipy.com/md.gif","width":498,"height":374,"size":285228},
                         "webp":{"url":"https://static.klipy.com/md.webp","width":498,"height":374},
                         "mp4":{"url":"https://static.klipy.com/md.mp4","width":498,"height":374},
                         "jpg":{"url":"https://static.klipy.com/md.jpg","width":498,"height":374},
                         "webm":[]},
                   "sm":{"gif":{"url":"https://static.klipy.com/sm.gif","width":220,"height":165},
                         "webp":{"url":"https://static.klipy.com/sm.webp","width":220,"height":165}}}},
          {"id":"2","slug":"ohne-datei","title":"weg"},
          {"id":3,"slug":"nur-sm","title":null,"file":{"sm":{"gif":{"url":"https://static2.klipy.com/sm3.gif","width":200,"height":100}}}}
        ],"current_page":1,"per_page":24,"has_next":true}}
        """

    func testKlipyPageKeepsOrderSkipsItemsWithoutFileAndPicksSizes() throws {
        let page = try JSONDecoder().decode(KlipyPage.self, from: Data(Self.klipyPage.utf8))
        XCTAssertTrue(page.hasNext)
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.items.map(\.slug), ["hello-hi-662", "nur-sm"], "ohne file faellt weg, sonst Reihenfolge von KLIPY")
        let first = page.items[0]
        XCTAssertEqual(first.id, "8041071659142944")
        XCTAssertEqual(first.tileURL?.absoluteString, "https://static.klipy.com/sm.webp", "Kachel: sm, animiertes WebP")
        XCTAssertEqual(first.blurPreviewData, Data([0, 1, 2]))
        // Gesendet wird md (mit Groesse aus dessen gif).
        let input = try XCTUnwrap(first.gifInput)
        XCTAssertEqual(input.gifUrl, "https://static.klipy.com/md.gif")
        XCTAssertEqual(input.webpUrl, "https://static.klipy.com/md.webp")
        XCTAssertEqual(input.mp4Url, "https://static.klipy.com/md.mp4")
        XCTAssertEqual(input.stillUrl, "https://static.klipy.com/md.jpg")
        XCTAssertEqual(input.width, 498)
        XCTAssertEqual(input.height, 374)
        XCTAssertEqual(input.title, "Hello")
        // Ohne md und hd: sm.
        let small = try XCTUnwrap(page.items[1].gifInput)
        XCTAssertEqual(small.gifUrl, "https://static2.klipy.com/sm3.gif")
        XCTAssertNil(small.webpUrl)
        XCTAssertEqual(page.items[1].tileURL?.absoluteString, "https://static2.klipy.com/sm3.gif", "ohne WebP das GIF")
    }

    func testKlipyRequests() throws {
        let client = try XCTUnwrap(KlipyClient(config: GifConfig(enabled: true, apiKey: "key-1", customerId: "cust-9",
                                                                 locale: "de", contentFilter: "medium")))
        let trending = URLComponents(url: client.url(query: "  ", page: 1), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(trending.path, "/api/v1/key-1/gifs/trending")
        let items = Dictionary(uniqueKeysWithValues: (trending.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["page": "1", "per_page": "24", "customer_id": "cust-9", "locale": "de",
                               "content_filter": "medium"])
        let search = URLComponents(url: client.url(query: "Hallo Welt", page: 3), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(search.path, "/api/v1/key-1/gifs/search")
        XCTAssertEqual(search.queryItems?.first { $0.name == "q" }?.value, "Hallo Welt")
        XCTAssertEqual(search.queryItems?.first { $0.name == "page" }?.value, "3")
        XCTAssertEqual(search.host, "api.klipy.com", "direkt zu KLIPY, nicht ueber den Dienst")

        let share = client.shareRequest(slug: "hello-hi-662", query: " winken ")
        XCTAssertEqual(share.httpMethod, "POST")
        XCTAssertEqual(share.url?.path(), "/api/v1/key-1/gifs/share/hello-hi-662")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: share.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["customer_id": "cust-9", "q": "winken"])
    }

    // MARK: - Eigene GIFs

    func testImageFormatFromBytesAndContentType() {
        XCTAssertEqual(ImageFormat.sniff(Self.animatedGif()), .gif)
        XCTAssertEqual(ImageFormat.sniff(Data("GIF87a".utf8)), .gif)
        XCTAssertEqual(ImageFormat.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0])), .jpeg)
        XCTAssertEqual(ImageFormat.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), .png)
        XCTAssertEqual(ImageFormat.sniff(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)), .webp)
        XCTAssertNil(ImageFormat.sniff(Data("<html>".utf8)))
        XCTAssertNil(ImageFormat.sniff(Data()))
        XCTAssertEqual(ImageFormat.from(contentType: "image/gif"), .gif)
        XCTAssertEqual(ImageFormat.from(contentType: "Image/JPEG; charset=binary"), .jpeg)
        XCTAssertNil(ImageFormat.from(contentType: "application/json"))
        XCTAssertEqual(ImageFormat.gif.fileExtension, "gif")
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpg")
    }

    func testPickedGifStaysAGifAndAPhotoBecomesAnImage() throws {
        let gif = Self.animatedGif()
        guard case .gif(let data) = ChatAttachment.picked(gif) else { return XCTFail("ein GIF wird nicht erkannt") }
        XCTAssertEqual(data, gif, "unveraendert, nicht neu kodiert")
        XCTAssertNotNil(ChatAttachment.picked(gif)?.preview, "das erste Bild als Vorschau")
        XCTAssertEqual(ChatAttachment.picked(gif)?.uploadData, gif)

        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.jpegData(compressionQuality: 0.8))
        let photo = try XCTUnwrap(ChatAttachment.picked(jpeg))
        XCTAssertFalse(photo.isGif)
        XCTAssertEqual(ImageFormat.sniff(try XCTUnwrap(photo.uploadData)), .jpeg)
        XCTAssertNil(ChatAttachment.picked(Data("kein Bild".utf8)))
    }

    func testUploadSendsAGifAsGifAndAJpegAsJpeg() async throws {
        StubServer.install { _ in .json(201, #"{"id":"p-gif","width":4,"height":4,"animated":true}"#) }
        let upload = try await StubServer.api().uploadPhoto(data: Self.animatedGif(), key: "key-gif")
        XCTAssertEqual(upload.animated, true)
        let body = String(decoding: try XCTUnwrap(StubServer.requests.first?.body), as: UTF8.self)
        XCTAssertTrue(body.contains(#"filename="photo.gif""#))
        XCTAssertTrue(body.contains("Content-Type: image/gif"))

        StubServer.install { _ in .json(201, #"{"id":"p-jpg","width":4,"height":4}"#) }
        let jpeg = try await StubServer.api().uploadPhoto(data: Data([0xFF, 0xD8, 0xFF, 0xE0]), key: "key-jpg")
        XCTAssertNil(jpeg.animated, "ein aelterer Dienst schickt animated nicht")
        let jpegBody = String(decoding: try XCTUnwrap(StubServer.requests.first?.body), as: UTF8.self)
        XCTAssertTrue(jpegBody.contains(#"filename="photo.jpg""#))
        XCTAssertTrue(jpegBody.contains("Content-Type: image/jpeg"))
    }

    func testOutboxKeepsAnOwnGifAndAKlipyGif() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = CohabitOutbox(directory: directory)
        let gif = Self.animatedGif()
        await outbox.enqueueMessage(cohabitId: "c1", request: MessageRequest(id: "m1", text: "Haha"), photo: gif)
        let input = GifInput(slug: "s", title: nil, width: 10, height: 10, gifUrl: "https://static.klipy.com/s.gif",
                             webpUrl: nil, mp4Url: nil, stillUrl: nil)
        await outbox.enqueueMessage(cohabitId: "c1", request: MessageRequest(id: "m2", text: nil, gif: input), photo: nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "photos").path())
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(".gif"), "die wartende Datei bleibt ein GIF")
        XCTAssertEqual(CohabitSync.shared.pendingMessages["c1"]?.last?.gif?.slug, "s")

        StubServer.install { request in
            request.path.hasSuffix("/photos") ? .json(201, #"{"id":"p-gif","width":4,"height":4,"animated":true}"#)
                                              : .json(201, "{}")
        }
        await outbox.replay(using: StubServer.api())
        let requests = StubServer.requests
        XCTAssertEqual(requests.map(\.path), ["/cohabit/api/photos", "/cohabit/api/cohabits/c1/messages",
                                              "/cohabit/api/cohabits/c1/messages"])
        let upload = String(decoding: requests[0].body, as: UTF8.self)
        XCTAssertTrue(upload.contains("Content-Type: image/gif"))
        XCTAssertEqual(requests[0].headers["Idempotency-Key"], (files[0] as NSString).deletingPathExtension)
        XCTAssertEqual(requests[1].json?["photoId"] as? String, "p-gif")
        XCTAssertEqual((requests[2].json?["gif"] as? [String: Any])?["slug"] as? String, "s")
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        CohabitSync.shared.reset()
    }
}
