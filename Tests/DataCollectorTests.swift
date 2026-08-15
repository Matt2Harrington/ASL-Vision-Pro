import XCTest

/// The collector produces the training set, so its output format is a hard contract with
/// `training/import_recordings.py`. If the shape or keys drift, the importer silently skips
/// every clip — which is why the format is asserted explicitly here.
@MainActor
final class DataCollectorTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recordings-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private func frames(_ count: Int) -> [SignFrame] {
        let lm = [Landmark(position: CGPoint(x: 0.5, y: 0.5), z: 0.1, confidence: 1)]
        return (0..<count).map { i in
            SignFrame(timestamp: TimeInterval(i),
                      leftHand: Array(repeating: lm[0], count: 21),
                      rightHand: Array(repeating: lm[0], count: 21),
                      body: Array(repeating: lm[0], count: 8),
                      face: Array(repeating: lm[0], count: 16))
        }
    }

    private func makeCollector(prompts: [String] = ["HELLO", "PLEASE"]) -> DataCollector {
        DataCollector(prompts: prompts,
                      source: MockSignFrameSource(),
                      signerID: "test-signer",
                      outputURL: tempURL,
                      clipDuration: 0.01)
    }

    // MARK: - Clip validation

    /// A clip shorter than one model window can't be encoded, so it must be rejected rather
    /// than written as a malformed record.
    func testShortClipsAreRejected() {
        XCTAssertFalse(DataCollector.isClipLongEnough(frames(5)))
        XCTAssertFalse(DataCollector.isClipLongEnough([]))
        XCTAssertFalse(DataCollector.isClipLongEnough(frames(FeatureEncoder.sequenceLength - 1)))
    }

    func testFullLengthClipIsAccepted() {
        XCTAssertTrue(DataCollector.isClipLongEnough(frames(FeatureEncoder.sequenceLength)))
        XCTAssertTrue(DataCollector.isClipLongEnough(frames(100)))
    }

    // MARK: - Output format (contract with import_recordings.py)

    func testWritesDecodableRecordWithExpectedShape() throws {
        try DataCollector.appendRecording(gloss: "HELLO", signerID: "matt",
                                          frames: frames(30), to: tempURL)

        let line = try XCTUnwrap(contents().first)
        let record = try JSONDecoder().decode(DataCollector.Recording.self,
                                              from: Data(line.utf8))

        XCTAssertEqual(record.gloss, "HELLO")
        XCTAssertEqual(record.signer, "matt")
        XCTAssertEqual(record.features.count, FeatureEncoder.sequenceLength,
                       "importer expects exactly sequenceLength rows")
        XCTAssertEqual(record.features.first?.count, FeatureEncoder.featuresPerFrame,
                       "importer expects featuresPerFrame columns (198 with 3D)")
    }

    /// Newline-delimited: the importer reads one JSON object per line.
    func testAppendsOnePerLine() throws {
        try DataCollector.appendRecording(gloss: "HELLO", signerID: "a", frames: frames(30), to: tempURL)
        try DataCollector.appendRecording(gloss: "PLEASE", signerID: "a", frames: frames(30), to: tempURL)
        try DataCollector.appendRecording(gloss: "YES", signerID: "b", frames: frames(30), to: tempURL)

        let lines = contents()
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            XCTAssertNoThrow(try JSONDecoder().decode(DataCollector.Recording.self,
                                                       from: Data(line.utf8)),
                             "every line must independently decode")
        }
    }

    /// Long clips are trimmed to the window by the encoder, not written raw.
    func testLongClipIsTrimmedToWindow() throws {
        try DataCollector.appendRecording(gloss: "HELLO", signerID: "a",
                                          frames: frames(500), to: tempURL)
        let record = try JSONDecoder().decode(DataCollector.Recording.self,
                                               from: Data(try XCTUnwrap(contents().first).utf8))
        XCTAssertEqual(record.features.count, FeatureEncoder.sequenceLength)
    }

    /// Signer must survive into the file — training splits by signer, so losing it would
    /// invalidate validation accuracy.
    func testSignerIsPreserved() throws {
        try DataCollector.appendRecording(gloss: "HELLO", signerID: "signer-42",
                                          frames: frames(30), to: tempURL)
        let record = try JSONDecoder().decode(DataCollector.Recording.self,
                                               from: Data(try XCTUnwrap(contents().first).utf8))
        XCTAssertEqual(record.signer, "signer-42")
    }

    // MARK: - Session flow

    func testStartsOnFirstPrompt() {
        XCTAssertEqual(makeCollector().currentPrompt, "HELLO")
    }

    func testSkipAdvancesWithoutRecording() {
        let c = makeCollector()
        c.skip()
        XCTAssertEqual(c.currentPrompt, "PLEASE")
        XCTAssertEqual(c.clipsRecorded, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "skipping must not write a clip")
    }

    func testFinishingAllPromptsClearsCurrent() {
        let c = makeCollector(prompts: ["ONLY"])
        c.skip()
        XCTAssertNil(c.currentPrompt)
    }

    func testEmptyPromptListIsSafe() {
        let c = makeCollector(prompts: [])
        XCTAssertNil(c.currentPrompt)
        XCTAssertEqual(c.progress, 0, "must not divide by zero")
    }

    func testProgressAdvancesWithPrompts() {
        let c = makeCollector(prompts: ["A", "B", "C", "D"])
        XCTAssertEqual(c.progress, 0.0, accuracy: 0.001)
        c.skip()
        XCTAssertEqual(c.progress, 0.25, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func contents() -> [String] {
        (try? String(contentsOf: tempURL, encoding: .utf8))?
            .split(separator: "\n")
            .map(String.init) ?? []
    }
}
