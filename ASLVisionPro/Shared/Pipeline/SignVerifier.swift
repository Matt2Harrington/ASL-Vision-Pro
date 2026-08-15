import CoreML
import Foundation
import OSLog

/// Tutor-mode recognition: **verification**, not open recognition.
///
/// This is the key insight behind Direction 1 (ALTERNATIVE_DIRECTIONS.md). A tutor already
/// knows which sign the learner is attempting, so the question changes from
///   "which of N signs is this?"        (hard, needs data for every class)
/// to
///   "is this a correct THANK-YOU?"     (1-vs-rest, far easier, degrades gracefully)
///
/// A wrong answer here means "try again", not a mistranslation — a much lower-stakes failure
/// mode than live interpretation.
protocol SignVerifying {
    /// Score an attempt against the expected sign.
    func verify(_ window: SignSegmenter.Window, expecting expected: String) async -> SignAttempt?
}

/// The result of one attempt at a target sign.
struct SignAttempt {
    let expected: String
    /// Model confidence that the attempt matches `expected`, in [0, 1].
    let score: Float
    /// What the model thought it saw instead, when the attempt missed. Nil when correct or
    /// when the recognizer can't say.
    let confusedWith: String?
    let timestamp: TimeInterval

    /// Tuned so learners get credit for a recognizable attempt without rewarding noise.
    var isCorrect: Bool { score >= 0.6 }

    var feedback: Feedback {
        switch score {
        case 0.85...:      return .excellent
        case 0.6..<0.85:   return .good
        case 0.35..<0.6:   return .close
        default:           return .tryAgain
        }
    }

    enum Feedback {
        case excellent, good, close, tryAgain

        var message: String {
            switch self {
            case .excellent: return "Excellent"
            case .good:      return "Good"
            case .close:     return "Close — keep going"
            case .tryAgain:  return "Try again"
            }
        }
    }
}

/// Verifier backed by the same Core ML classifier used for recognition: run the classifier,
/// then read off the probability assigned to the expected class. Reusing one model keeps the
/// training pipeline single-track — no separate per-sign models to maintain.
final class CoreMLSignVerifier: SignVerifying {
    private let log = Logger(subsystem: "ASLVisionPro", category: "Verifier")
    private let model: MLModel
    private let labels: [String]

    init(model: MLModel, labels: [String]) {
        self.model = model
        self.labels = labels
    }

    func verify(_ window: SignSegmenter.Window, expecting expected: String) async -> SignAttempt? {
        guard let expectedIndex = labels.firstIndex(of: expected) else {
            log.error("Expected sign '\(expected)' is not in the model's label set.")
            return nil
        }
        guard let input = FeatureEncoder.encode(window) else { return nil }

        do {
            let output = try await model.prediction(from: input)
            guard let probs = output.featureValue(for: "probabilities")?.multiArrayValue,
                  expectedIndex < probs.count else { return nil }

            let score = probs[expectedIndex].floatValue

            // Report the winning class when it isn't the target — that's the actionable part
            // of the feedback ("that looked like PLEASE").
            var topIndex = 0
            var topValue = -Float.greatestFiniteMagnitude
            for i in 0..<probs.count {
                let v = probs[i].floatValue
                if v > topValue { topValue = v; topIndex = i }
            }
            let confused = (topIndex != expectedIndex && topIndex < labels.count) ? labels[topIndex] : nil

            let ts = window.frames.last?.timestamp ?? 0
            return SignAttempt(expected: expected, score: score, confusedWith: confused, timestamp: ts)
        } catch {
            log.error("Verification failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Stub verifier for bring-up before a model exists — lets the tutor UI and lesson flow be
/// exercised end-to-end. Cycles deterministically so the UI states are all reachable.
final class StubSignVerifier: SignVerifying {
    private var counter = 0

    func verify(_ window: SignSegmenter.Window, expecting expected: String) async -> SignAttempt? {
        counter += 1
        let scores: [Float] = [0.9, 0.7, 0.45, 0.2]
        let score = scores[counter % scores.count]
        return SignAttempt(
            expected: expected,
            score: score,
            confusedWith: score < 0.6 ? "PLEASE" : nil,
            timestamp: window.frames.last?.timestamp ?? 0
        )
    }
}
