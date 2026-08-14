import XCTest

/// Covers the three caption behaviors: fingerspelling builds words, isolated signs
/// accumulate as tokens, and continuous phrases REPLACE the line (revisable captions).
final class CaptionAssemblerTests: XCTestCase {

    private func result(_ text: String, _ kind: RecognitionResult.Kind,
                        _ ts: TimeInterval = 0) -> RecognitionResult {
        RecognitionResult(text: text, confidence: 0.9, timestamp: ts, kind: kind)
    }

    func testLettersBuildUpAWord() {
        let a = CaptionAssembler()
        _ = a.append(result("C", .letter))
        _ = a.append(result("A", .letter))
        let out = a.append(result("T", .letter))
        XCTAssertEqual(out, "CAT")
    }

    /// A sign between fingerspelled runs must end the first word and start a new one —
    /// letters must not glue onto the sign token.
    func testSignBreaksFingerspelledWord() {
        let a = CaptionAssembler()
        _ = a.append(result("J", .letter))
        _ = a.append(result("O", .letter))
        _ = a.append(result("HELLO", .sign))
        _ = a.append(result("A", .letter))
        let out = a.append(result("B", .letter))
        XCTAssertEqual(out, "JO HELLO AB")
    }

    func testSignsAccumulateAsSeparateTokens() {
        let a = CaptionAssembler()
        _ = a.append(result("HELLO", .sign))
        let out = a.append(result("FRIEND", .sign))
        XCTAssertEqual(out, "HELLO FRIEND")
    }

    /// Overlapping segmenter windows re-emit the same sign; it should not duplicate.
    func testDuplicateConsecutiveRecognitionIsCollapsed() {
        let a = CaptionAssembler()
        _ = a.append(result("HELLO", .sign))
        let out = a.append(result("HELLO", .sign))
        XCTAssertEqual(out, "HELLO")
    }

    /// Continuous decoding re-decodes the whole rolling context each pass, so a phrase
    /// replaces the caption rather than appending to it.
    func testPhraseReplacesRatherThanAppends() {
        let a = CaptionAssembler()
        _ = a.append(result("I AM", .phrase))
        let out = a.append(result("I AM GOING HOME", .phrase))
        XCTAssertEqual(out, "I AM GOING HOME")
    }

    func testPhraseSupersedesEarlierTokens() {
        let a = CaptionAssembler()
        _ = a.append(result("HELLO", .sign))
        let out = a.append(result("HELLO HOW ARE YOU", .phrase))
        XCTAssertEqual(out, "HELLO HOW ARE YOU")
    }
}
