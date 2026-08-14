import CoreML
import Foundation
import OSLog

/// Level-3 recognizer (ARCHITECTURE.md capability ladder; RECOGNITION_APPROACH.md §Level 3).
///
/// Continuous signing has no boundaries between signs, so a per-window *classifier* can't
/// work — you must map an unsegmented motion stream to a token sequence. This uses **CTC**
/// (Connectionist Temporal Classification): the model emits per-timestep logits over a
/// vocabulary + a blank symbol, and greedy CTC decoding collapses them into tokens without
/// needing frame-level alignment.
///
/// This is a SCAFFOLD — it plugs into the same `SignRecognizing` seam the classifier uses,
/// proving the Level-3 path end-to-end before a CTC model exists. Drop in a trained
/// `SignCTCModel.mlpackage` (input `landmarks` [1, T, 132], output `logits` [1, T, V]) and
/// a vocabulary, and it runs.
///
/// Alternative not taken here: a true **seq2seq / SLT** encoder–decoder yields more fluent
/// English but requires an autoregressive decode loop (and often a KV cache) on device — a
/// much larger lift than CTC greedy decoding. CTC gives sign *order*; seq2seq gives fluent
/// translation. Both sit behind this same protocol; only `recognize` changes.
final class ContinuousSignRecognizer: SignRecognizing {
    private let log = Logger(subsystem: "ASLVisionPro", category: "ContinuousRecognizer")
    private let model: MLModel
    private let vocab: [String]
    private let blankIndex: Int
    private let contextFrames: Int

    /// Rolling context of recent frames. Continuous recognition needs a longer, sliding
    /// window than a single sign, so we accumulate across calls rather than decode each
    /// segmenter window in isolation.
    private var buffer: [SignFrame] = []
    private var lastTimestamp: TimeInterval = 0

    init(model: MLModel, vocab: [String], blankIndex: Int = 0, contextFrames: Int = 64) {
        self.model = model
        self.vocab = vocab
        self.blankIndex = blankIndex
        self.contextFrames = contextFrames
    }

    func recognize(_ window: SignSegmenter.Window) async -> RecognitionResult? {
        appendNewFrames(window.frames)
        guard buffer.count >= contextFrames / 2 else { return nil }   // wait for enough context

        guard let input = FeatureEncoder.encodeSequence(buffer, length: contextFrames) else { return nil }
        do {
            let output = try await model.prediction(from: input)
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                log.error("CTC model produced no 'logits' output.")
                return nil
            }
            let tokens = CTCDecoder.greedyDecode(logits: logits, blankIndex: blankIndex, vocab: vocab)
            guard !tokens.isEmpty else { return nil }
            let text = tokens.joined(separator: " ")
            // NOTE: CTC greedy decoding has no clean per-sequence confidence; a proper value
            // needs beam-search scores. Placeholder until then.
            return RecognitionResult(text: text, confidence: 0.5, timestamp: lastTimestamp, kind: .phrase)
        } catch {
            log.error("CTC prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Append frames newer than what we've already buffered (segmenter windows overlap),
    /// keeping only the most recent `contextFrames`.
    private func appendNewFrames(_ frames: [SignFrame]) {
        for f in frames where f.timestamp > lastTimestamp {
            buffer.append(f)
            lastTimestamp = f.timestamp
        }
        if buffer.count > contextFrames {
            buffer.removeFirst(buffer.count - contextFrames)
        }
    }
}

/// Greedy CTC decoding: argmax per timestep, drop blanks, collapse consecutive repeats.
/// Pure and self-contained so it can be unit-tested without a model.
enum CTCDecoder {
    static func greedyDecode(logits: MLMultiArray, blankIndex: Int, vocab: [String]) -> [String] {
        // Expect shape [1, T, V].
        guard logits.shape.count == 3 else { return [] }
        let T = logits.shape[1].intValue
        let V = logits.shape[2].intValue
        guard T > 0, V > 0 else { return [] }

        var out: [String] = []
        var previous = -1
        for t in 0..<T {
            var bestIndex = 0
            var bestValue = -Float.greatestFiniteMagnitude
            for v in 0..<V {
                let value = logits[[0, NSNumber(value: t), NSNumber(value: v)]].floatValue
                if value > bestValue { bestValue = value; bestIndex = v }
            }
            // CTC collapse rule: skip blanks and repeats of the previous emitted symbol.
            if bestIndex != blankIndex && bestIndex != previous && bestIndex < vocab.count {
                out.append(vocab[bestIndex])
            }
            previous = bestIndex
        }
        return out
    }
}
