import XCTest

/// Covers English → gloss mapping. This is deliberately Signed-English word order, not full
/// ASL grammar, so the tests assert the behaviours that make it *useful* — dropped function
/// words, synonym mapping, and fingerspelling fallback — not translation fluency.
final class GlossTranslatorTests: XCTestCase {

    private func makeTranslator() -> GlossTranslator {
        GlossTranslator(catalog: SignCatalog(bundle: Bundle(for: type(of: self))))
    }

    func testKnownWordsMapToSigns() {
        let tokens = makeTranslator().translate("hello friend")
        XCTAssertEqual(tokens.map(\.display), ["HELLO", "FRIEND"])
    }

    /// ASL omits English articles and copulas; dropping them is closer to ASL than signing
    /// them literally.
    func testFunctionWordsAreDropped() {
        let tokens = makeTranslator().translate("the water is good")
        XCTAssertEqual(tokens.map(\.display), ["WATER", "GOOD"])
    }

    func testSynonymsMapToCanonicalGloss() {
        let t = makeTranslator()
        XCTAssertEqual(t.translate("hi").map(\.display), ["HELLO"])
        XCTAssertEqual(t.translate("thanks").map(\.display), ["THANK-YOU"])
        XCTAssertEqual(t.translate("restroom").map(\.display), ["BATHROOM"])
    }

    /// Out-of-vocabulary words fall back to fingerspelling — what a human interpreter does
    /// for names and unknown terms.
    func testUnknownWordsFallBackToFingerspelling() {
        let tokens = makeTranslator().translate("matt")
        guard case .fingerspell(let word)? = tokens.first else {
            return XCTFail("expected a fingerspell token, got \(tokens)")
        }
        XCTAssertEqual(word, "matt")
    }

    func testMixedSentenceSplitsSignsAndFingerspelling() {
        let tokens = makeTranslator().translate("hello zephyr")
        XCTAssertEqual(tokens.count, 2)
        if case .sign(let e) = tokens[0] { XCTAssertEqual(e.gloss, "HELLO") } else { XCTFail("expected sign") }
        if case .fingerspell = tokens[1] {} else { XCTFail("expected fingerspell") }
    }

    func testPunctuationAndCaseAreHandled() {
        let tokens = makeTranslator().translate("Hello, FRIEND!")
        XCTAssertEqual(tokens.map(\.display), ["HELLO", "FRIEND"])
    }

    /// Coverage drives an honest indicator in the UI — it should reflect the true ratio of
    /// real signs to fingerspelled words.
    func testCoverageReflectsSignRatio() {
        let t = makeTranslator()
        XCTAssertEqual(t.coverage(of: t.translate("hello friend")), 1.0, accuracy: 0.001)
        XCTAssertEqual(t.coverage(of: t.translate("zephyr qwertz")), 0.0, accuracy: 0.001)
        XCTAssertEqual(t.coverage(of: t.translate("hello zephyr")), 0.5, accuracy: 0.001)
    }

    func testEmptyInputProducesNoTokens() {
        XCTAssertTrue(makeTranslator().translate("").isEmpty)
        XCTAssertEqual(makeTranslator().coverage(of: []), 0)
    }
}
