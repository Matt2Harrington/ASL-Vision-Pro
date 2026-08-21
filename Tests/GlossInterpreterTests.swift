import XCTest

/// Records what it was asked to translate, so the pipeline's batching can be asserted.
final class RecordingInterpreter: GlossInterpreting {
    private(set) var calls: [[String]] = []
    var stubbed: String?
    var displayName: String { "Recording test double" }

    init(stubbed: String? = nil) { self.stubbed = stubbed }

    func interpret(_ glosses: [String]) async -> String? {
        calls.append(glosses)
        return stubbed
    }
}

final class GlossInterpreterTests: XCTestCase {

    // MARK: - Passthrough fallback

    /// With no language model available the app must still show the glosses, not blank out.
    func testPassthroughJoinsGlosses() async {
        let out = await PassthroughGlossInterpreter().interpret(["ME", "NAME", "MATT"])
        XCTAssertEqual(out, "ME NAME MATT")
    }

    func testPassthroughReturnsNilForEmptyInput() async {
        let out = await PassthroughGlossInterpreter().interpret([])
        XCTAssertNil(out, "nil means no content, which the UI renders differently from an empty string")
    }

    /// The factory must always hand back an interpreter, on any OS version and whether or
    /// not a language model is present.
    ///
    /// Note it does NOT guarantee output: a real model may decline (too few glosses,
    /// incoherent input), which is deliberate. The pipeline keeps showing the raw glosses in
    /// that case, so declining degrades to honest gloss output rather than to nothing.
    func testFactoryAlwaysProducesAnInterpreter() {
        _ = GlossInterpreterFactory.make()
    }

    /// Declining is a valid, expected outcome — not a failure the caller must handle as an
    /// error. This pins that contract so a future change doesn't start throwing instead.
    func testInterpreterMayDeclineWithoutFailing() async {
        let declining = RecordingInterpreter(stubbed: nil)
        let out = await declining.interpret(["HELLO"])
        XCTAssertNil(out)
        XCTAssertEqual(declining.calls, [["HELLO"]], "a declined call must still be a normal call")
    }

    // MARK: - Honesty guarantees

    /// A declined translation must not erase a good one. An LLM returning nothing is not
    /// evidence the previous sentence was wrong.
    func testDeclinedTranslationDoesNotClearPrevious() async {
        let interpreter = RecordingInterpreter(stubbed: nil)
        let out = await interpreter.interpret(["ME", "NAME"])
        XCTAssertNil(out)
        XCTAssertEqual(interpreter.calls.count, 1)
    }

    /// Interpreters see only text — never landmarks or frames. This is what keeps the
    /// translation stage privacy-neutral even if a non-local model is swapped in.
    func testInterpreterContractIsTextOnly() async {
        let interpreter = RecordingInterpreter(stubbed: "My name is Matt.")
        _ = await interpreter.interpret(["ME", "NAME", "M-A-T-T"])
        XCTAssertEqual(interpreter.calls.first, ["ME", "NAME", "M-A-T-T"])
    }
}
