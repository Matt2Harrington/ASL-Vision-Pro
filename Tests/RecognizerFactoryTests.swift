import XCTest

/// The factory is what makes "drop in a model" a zero-code change on both platforms, so its
/// fallback behavior matters: with no model bundled it must degrade to stubs rather than
/// crash or return nil.
final class RecognizerFactoryTests: XCTestCase {

    /// No model is bundled in the test target, so every mode must fall back cleanly.
    func testFallsBackToStubRecognizerWithoutAModel() {
        XCTAssertTrue(RecognizerFactory.makeRecognizer() is StubSignRecognizer)
        XCTAssertTrue(RecognizerFactory.makeRecognizer(mode: .isolated) is StubSignRecognizer)
        XCTAssertTrue(RecognizerFactory.makeRecognizer(mode: .continuous) is StubSignRecognizer)
        XCTAssertTrue(RecognizerFactory.makeRecognizer(mode: .automatic) is StubSignRecognizer)
    }

    /// Tutor mode has its own factory path; without it `CoreMLSignVerifier` would be
    /// unreachable and the tutor would silently stay on the stub after a model shipped.
    func testFallsBackToStubVerifierWithoutAModel() {
        XCTAssertTrue(RecognizerFactory.makeVerifier() is StubSignVerifier)
    }

    /// The stub must still drive the pipeline end-to-end so bring-up works pre-model.
    func testStubRecognizerProducesAResult() async {
        let frames = (0..<24).map { i in
            SignFrame(timestamp: TimeInterval(i),
                      leftHand: [Landmark(position: .zero, z: 0, confidence: 1)],
                      rightHand: [], body: [], face: [])
        }
        let result = await StubSignRecognizer().recognize(.init(frames: frames))
        XCTAssertNotNil(result)
        XCTAssertLessThan(result?.confidence ?? 1, 0.5,
                          "stub output must be low-confidence so it can't be mistaken for real recognition")
    }

    /// The stub verifier must reach every feedback tier so the tutor UI can be exercised
    /// before a model exists.
    func testStubVerifierCyclesThroughFeedbackTiers() async {
        let verifier = StubSignVerifier()
        let frames = [SignFrame(timestamp: 0, leftHand: [], rightHand: [], body: [], face: [])]
        var tiers = Set<String>()
        for _ in 0..<8 {
            if let a = await verifier.verify(.init(frames: frames), expecting: "HELLO") {
                tiers.insert(a.feedback.message)
            }
        }
        XCTAssertGreaterThanOrEqual(tiers.count, 3, "stub should exercise multiple UI states")
    }
}
