import XCTest

/// Speaking puts words in the signer's mouth, so the guards around *when* it speaks matter
/// more than the synthesis itself. These pin the conditions rather than the audio.
@MainActor
final class SignSpeakerTests: XCTestCase {

    private func makeSpeaker(enabled: Bool = true,
                             mode: SignSpeaker.Mode = .word) -> SignSpeaker {
        let s = SignSpeaker()
        s.isEnabled = enabled
        s.mode = mode
        return s
    }

    // MARK: - When it must stay silent

    /// Off by default: the app must not start speaking on someone's behalf unprompted.
    func testDisabledByDefault() {
        XCTAssertFalse(SignSpeaker().isEnabled)
    }

    func testSaysNothingWhenDisabled() {
        let s = makeSpeaker(enabled: false)
        s.speak(sign: "HELLO", confidence: 1.0)
        XCTAssertNil(s.lastSpoken)
    }

    /// The bar for speaking is higher than for displaying — a wrong caption can be read past,
    /// a wrong word cannot be unsaid.
    func testIgnoresLowConfidence() {
        let s = makeSpeaker()
        s.speak(sign: "HELLO", confidence: s.threshold - 0.01)
        XCTAssertNil(s.lastSpoken)
    }

    func testSpeaksAtOrAboveThreshold() {
        let s = makeSpeaker()
        s.speak(sign: "HELLO", confidence: s.threshold)
        XCTAssertEqual(s.lastSpoken, "HELLO")
    }

    /// NONE is the model abstaining. Saying "none" aloud would be nonsense.
    func testNeverSpeaksTheRestLabel() {
        let s = makeSpeaker()
        s.speak(sign: CoreMLSignRecognizer.restLabel, confidence: 1.0)
        XCTAssertNil(s.lastSpoken)
    }

    // MARK: - Repeats

    /// A sign held across several windows re-fires recognition; without suppression the same
    /// word is spoken over and over.
    func testSuppressesImmediateRepeat() {
        let s = makeSpeaker()
        s.speak(sign: "WATER", confidence: 1.0)
        s.speak(sign: "WATER", confidence: 1.0)
        // lastSpoken reads the same either way, which is exactly why the count exists.
        XCTAssertEqual(s.utteranceCount, 1, "a repeat inside the window should be swallowed")
    }

    func testDifferentSignSpeaksImmediately() {
        let s = makeSpeaker()
        s.speak(sign: "WATER", confidence: 1.0)
        s.speak(sign: "PLEASE", confidence: 1.0)
        XCTAssertEqual(s.lastSpoken, "PLEASE", "a different sign is not a repeat")
        XCTAssertEqual(s.utteranceCount, 2)
    }

    // MARK: - Modes

    /// The two modes must not both speak the same utterance.
    func testWordModeIgnoresSentences() {
        let s = makeSpeaker(mode: .word)
        s.speak(sentence: "My name is Matt.")
        XCTAssertNil(s.lastSpoken)
    }

    func testSentenceModeIgnoresIndividualSigns() {
        let s = makeSpeaker(mode: .sentence)
        s.speak(sign: "HELLO", confidence: 1.0)
        XCTAssertNil(s.lastSpoken)
    }

    func testSentenceModeSpeaksSentences() {
        let s = makeSpeaker(mode: .sentence)
        s.speak(sentence: "My name is Matt.")
        XCTAssertEqual(s.lastSpoken, "My name is Matt.")
    }

    /// Hyphens are gloss notation, not pronunciation — THANK-YOU should be said as words.
    func testGlossHyphensBecomeSpaces() {
        let s = makeSpeaker()
        s.speak(sign: "THANK-YOU", confidence: 1.0)
        XCTAssertEqual(s.lastSpoken, "THANK YOU")
    }

    func testEmptyInputIsIgnored() {
        let s = makeSpeaker(mode: .sentence)
        s.speak(sentence: "   ")
        XCTAssertNil(s.lastSpoken)
    }
}
