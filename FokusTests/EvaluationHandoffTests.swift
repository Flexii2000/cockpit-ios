import XCTest
@testable import Fokus

/// Der Umzug der Evaluation von Healthy nach Fokus (14.10.): keine Antwort darf
/// verloren gehen. Healthy bietet an (`EvaluationHandoff.offer`), Fokus
/// uebernimmt (`EvaluationImport.run`) - hier mit einem Woerterbuch statt des
/// Schluesselbunds und Dateien im Temp-Ordner. Platzhalter statt echter Fragen.
final class EvaluationHandoffTests: XCTestCase {

    /// Der Schluesselbund als Woerterbuch.
    private final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Data] = [:]
        var failWrites = false

        subscript(key: String) -> Data? {
            lock.withLock { items[key] }
        }

        var slot: EvaluationHandoff.Slot {
            EvaluationHandoff.Slot(
                read: { key in self.lock.withLock { self.items[key] } },
                write: { data, key in
                    self.lock.withLock {
                        guard !self.failWrites else { return false }
                        self.items[key] = data
                        return true
                    }
                },
                delete: { key in self.lock.withLock { self.items[key] = nil } })
        }
    }

    private let question = EvaluationQuestion(text: "Frage A")
    private let monday = CalendarDate(year: 2026, month: 10, day: 12)
    private var memory = Memory()

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ data: EvaluationData, to file: URL) throws -> Data {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(data)
        try bytes.write(to: file)
        return bytes
    }

    private func answered(_ value: Int) -> EvaluationData {
        var data = EvaluationData(questions: [question])
        data.set(value, for: question.id, on: monday)
        return data
    }

    override func setUp() {
        super.setUp()
        memory = Memory()
    }

    // MARK: - Healthy bietet an

    func testHealthyWithoutAFileOffersNothing() {
        let healthy = folder().appendingPathComponent("evaluation.json")
        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .noFile)
        XCTAssertNil(memory[EvaluationHandoff.handoffKey])
    }

    func testHealthyOffersItsBytesOnceAndKeepsItsFile() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let bytes = try write(answered(7), to: healthy)

        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .offered)
        XCTAssertEqual(memory[EvaluationHandoff.handoffKey], bytes, "Byte fuer Byte")
        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .alreadyOffered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: healthy.path), "Healthy behaelt seine Datei als Sicherung")
    }

    func testAFailedWriteIsReportedSoTheNextStartTriesAgain() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        _ = try write(answered(7), to: healthy)
        memory.failWrites = true

        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .failed)
        memory.failWrites = false
        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .offered)
    }

    // MARK: - Fokus uebernimmt

    func testFokusImportsIntoAnEmptyPlaceAndAcknowledges() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("Evaluation/evaluation.json")
        let bytes = try write(answered(7), to: healthy)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .imported)

        XCTAssertEqual(try Data(contentsOf: fokus), bytes)
        XCTAssertEqual(try EvaluationStore.read(fokus), answered(7))
        XCTAssertNil(memory[EvaluationHandoff.handoffKey], "der Eintrag ist weg")
        XCTAssertEqual(EvaluationHandoff.offer(file: healthy, slot: memory.slot), .alreadyImported,
                       "Healthy bietet denselben Stand nicht noch einmal an")
        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .nothing)
    }

    /// Fokus hatte schon Fragen, aber keine Antwort - ein frischer Anfang, der ersetzt wird.
    func testFokusWithOnlyQuestionsIsReplaced() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("evaluation.json")
        _ = try write(EvaluationData(questions: [EvaluationQuestion(text: "Frage B")]), to: fokus)
        _ = try write(answered(7), to: healthy)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .imported)
        XCTAssertEqual(try EvaluationStore.read(fokus), answered(7))
    }

    /// Fokus hatte schon eigene Antworten: nichts ueberschreiben, nichts verwerfen.
    func testFokusWithAnswersKeepsBoth() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("evaluation.json")
        _ = try write(answered(3), to: fokus)
        let bytes = try write(answered(7), to: healthy)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .keptBoth)

        XCTAssertEqual(try EvaluationStore.read(fokus), answered(3), "die eigenen Antworten bleiben")
        let side = fokus.deletingLastPathComponent().appendingPathComponent(EvaluationImport.sideFileName)
        XCTAssertEqual(try Data(contentsOf: side), bytes, "die aus Healthy liegen daneben")
        XCTAssertNil(memory[EvaluationHandoff.handoffKey])
    }

    /// Derselbe Stand noch einmal (Quittung ging verloren) - landet einfach wieder am selben Ort.
    func testTheSameStateTwiceIsHarmless() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("evaluation.json")
        _ = try write(answered(7), to: healthy)
        _ = try write(answered(7), to: fokus)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .imported)
        XCTAssertEqual(try EvaluationStore.read(fokus), answered(7))
    }

    /// Kein gueltiges JSON: der Eintrag bleibt liegen, nichts wird geschrieben.
    func testABrokenOfferIsLeftAlone() throws {
        let fokus = folder().appendingPathComponent("evaluation.json")
        _ = memory.slot.write(Data("kaputt".utf8), EvaluationHandoff.handoffKey)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .broken)
        XCTAssertNotNil(memory[EvaluationHandoff.handoffKey])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fokus.path))
    }

    /// Die Fokus-Datei ist da, aber nicht lesbar (etwa gesperrt): spaeter noch einmal, nichts anfassen.
    func testAnUnreadableTargetWaits() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("evaluation.json")
        try FileManager.default.createDirectory(at: fokus.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nicht lesbar".utf8).write(to: fokus)
        _ = try write(answered(7), to: healthy)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .later)
        XCTAssertEqual(try Data(contentsOf: fokus), Data("nicht lesbar".utf8))
        XCTAssertNotNil(memory[EvaluationHandoff.handoffKey])
    }

    /// Scheitert die Quittung, bleibt der Eintrag - Healthy bietet beim naechsten Start noch einmal an.
    func testWithoutReceiptTheOfferStays() throws {
        let healthy = folder().appendingPathComponent("evaluation.json")
        let fokus = folder().appendingPathComponent("evaluation.json")
        _ = try write(answered(7), to: healthy)
        EvaluationHandoff.offer(file: healthy, slot: memory.slot)
        memory.failWrites = true

        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .later)
        XCTAssertNotNil(memory[EvaluationHandoff.handoffKey])
        memory.failWrites = false
        XCTAssertEqual(EvaluationImport.run(file: fokus, slot: memory.slot), .imported)
    }
}
