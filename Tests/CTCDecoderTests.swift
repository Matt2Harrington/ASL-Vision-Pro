import XCTest
import CoreML

/// Locks down the CTC greedy-decode collapse rules independently of any model.
final class CTCDecoderTests: XCTestCase {

    /// Build a [1, T, V] logits array whose argmax at each timestep is `argmaxPerStep[t]`.
    private func makeLogits(_ argmaxPerStep: [Int], vocabSize: Int) -> MLMultiArray {
        let T = argmaxPerStep.count
        let a = try! MLMultiArray(shape: [1, NSNumber(value: T), NSNumber(value: vocabSize)],
                                  dataType: .float32)
        for t in 0..<T {
            for v in 0..<vocabSize {
                a[[0, NSNumber(value: t), NSNumber(value: v)]] =
                    NSNumber(value: v == argmaxPerStep[t] ? 1.0 : 0.0)
            }
        }
        return a
    }

    func testCollapsesRepeatsAndDropsBlanks() {
        let vocab = ["_", "A", "B"]                       // blank at index 0
        let logits = makeLogits([1, 1, 0, 2], vocabSize: 3)  // A, A(repeat), blank, B
        let out = CTCDecoder.greedyDecode(logits: logits, blankIndex: 0, vocab: vocab)
        XCTAssertEqual(out, ["A", "B"])
    }

    func testAllBlanksProducesEmpty() {
        let vocab = ["_", "A"]
        let logits = makeLogits([0, 0, 0], vocabSize: 2)
        XCTAssertEqual(CTCDecoder.greedyDecode(logits: logits, blankIndex: 0, vocab: vocab), [])
    }

    /// A repeat separated by a blank is TWO emissions — the defining CTC case.
    func testRepeatSeparatedByBlankKeepsBoth() {
        let vocab = ["_", "A"]
        let logits = makeLogits([1, 0, 1], vocabSize: 2)  // A, blank, A
        XCTAssertEqual(CTCDecoder.greedyDecode(logits: logits, blankIndex: 0, vocab: vocab), ["A", "A"])
    }

    func testConsecutiveRepeatCollapsesToOne() {
        let vocab = ["_", "A"]
        let logits = makeLogits([1, 1, 1], vocabSize: 2)  // A, A, A
        XCTAssertEqual(CTCDecoder.greedyDecode(logits: logits, blankIndex: 0, vocab: vocab), ["A"])
    }

    func testEmptyLogitsIsSafe() {
        let vocab = ["_", "A"]
        let a = try! MLMultiArray(shape: [1, 0, 2], dataType: .float32)
        XCTAssertEqual(CTCDecoder.greedyDecode(logits: a, blankIndex: 0, vocab: vocab), [])
    }
}
