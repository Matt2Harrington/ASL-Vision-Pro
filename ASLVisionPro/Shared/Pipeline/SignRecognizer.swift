import CoreML
import Foundation
import OSLog

/// Phase 2+ — the swappable ML stage (ARCHITECTURE.md §3).
///
/// This is intentionally the ONLY stage that knows about the model. Everything upstream
/// (capture, landmarks, segmentation) and downstream (captions) is model-agnostic, so a
/// larger model — or, if you ever revisit the on-device-only decision, an optional server
/// path — can be dropped in here without touching the rest of the app.
///
/// Until a trained Core ML model is dropped in (`SignModel.mlpackage`), this returns a
/// stub so the full pipeline runs end-to-end on device in Phase 1.
protocol SignRecognizing {
    func recognize(_ window: SignSegmenter.Window) async -> RecognitionResult?
}

/// Placeholder recognizer for Phase 0–1 bring-up. Emits a low-confidence "•" so the
/// caption path is visibly exercised without a model present.
final class StubSignRecognizer: SignRecognizing {
    func recognize(_ window: SignSegmenter.Window) async -> RecognitionResult? {
        guard let last = window.frames.last else { return nil }
        return RecognitionResult(text: "•", confidence: 0.1, timestamp: last.timestamp, kind: .sign)
    }
}

/// Real recognizer backed by a Core ML sequence model. Wire this up in Phase 2 once
/// `SignModel` has been trained and exported via coremltools (see MODEL_PLAN.md).
final class CoreMLSignRecognizer: SignRecognizing {
    private let log = Logger(subsystem: "ASLVisionPro", category: "Recognizer")
    private let model: MLModel
    private let labels: [String]
    /// Adjustable at runtime so the gate can be calibrated against real signing rather than
    /// guessed. Validation accuracy on a held-out set says little about where this should sit
    /// on a phone, in a room, with one person's hands.
    nonisolated(unsafe) var confidenceThreshold: Float
    nonisolated(unsafe) var requiredStreak: Int

    /// The most recent prediction, published whether or not it cleared the threshold.
    ///
    /// Without this a gated result is indistinguishable from the model never running, and
    /// "it isn't picking up my sign" can't be diagnosed on a phone. Reading this shows
    /// whether the model is confidently wrong, unconfidently right, or not firing at all.
    struct Peek: Sendable { let label: String; let confidence: Float; let accepted: Bool }
    private(set) nonisolated(unsafe) var lastPeek: Peek?

    /// A softmax over N signs always names one of them, however unlike the input is to
    /// anything the model saw in training — there is no "nothing" class, so pointing the
    /// camera at a room still yields a confident answer. Requiring the same label across
    /// consecutive windows filters that: noise jumps between classes, whereas a real sign
    /// held through a window persists.
    private nonisolated(unsafe) var streakLabel: String?
    private nonisolated(unsafe) var streakCount = 0

    /// Label the training set uses for "not signing".
    static let restLabel = "NONE"

    init(model: MLModel, labels: [String],
         confidenceThreshold: Float = 0.75,
         requiredStreak: Int = 2) {
        self.model = model
        self.labels = labels
        self.confidenceThreshold = confidenceThreshold
        self.requiredStreak = requiredStreak
    }

    func recognize(_ window: SignSegmenter.Window) async -> RecognitionResult? {
        guard let input = FeatureEncoder.encode(window) else { return nil }
        do {
            let output = try await model.prediction(from: input)
            guard let (label, confidence) = Self.topLabel(from: output, labels: labels) else {
                lastPeek = nil
                return nil
            }
            // NONE is the model abstaining — a real prediction, but not something to show.
            // Reaching it also clears any streak, so a sign has to be re-established rather
            // than resuming across a pause.
            if label == Self.restLabel {
                streakLabel = nil
                streakCount = 0
                lastPeek = Peek(label: label, confidence: confidence, accepted: false)
                return nil
            }

            if label == streakLabel {
                streakCount += 1
            } else {
                streakLabel = label
                streakCount = 1
            }

            let confident = confidence >= confidenceThreshold
            let stable = streakCount >= requiredStreak
            let accepted = confident && stable
            lastPeek = Peek(label: label, confidence: confidence, accepted: accepted)
            guard accepted else { return nil }

            // Consume the streak so one sustained sign emits once rather than repeating for
            // as long as it is held.
            streakCount = 0
            let ts = window.frames.last?.timestamp ?? 0
            return RecognitionResult(text: label, confidence: confidence, timestamp: ts, kind: .sign)
        } catch {
            log.error("Core ML prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads a softmax/probabilities output and returns the argmax label. Adjust the
    /// feature name (`"probabilities"`) to match the exported model's spec.
    private static func topLabel(from output: MLFeatureProvider, labels: [String]) -> (String, Float)? {
        guard let probs = output.featureValue(for: "probabilities")?.multiArrayValue else { return nil }
        var bestIndex = 0
        var bestValue: Float = -.greatestFiniteMagnitude
        for i in 0..<probs.count {
            let v = probs[i].floatValue
            if v > bestValue { bestValue = v; bestIndex = i }
        }
        guard bestIndex < labels.count else { return nil }
        return (labels[bestIndex], bestValue)
    }
}
