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
    private let confidenceThreshold: Float

    /// The most recent prediction, published whether or not it cleared the threshold.
    ///
    /// Without this a gated result is indistinguishable from the model never running, and
    /// "it isn't picking up my sign" can't be diagnosed on a phone. Reading this shows
    /// whether the model is confidently wrong, unconfidently right, or not firing at all.
    struct Peek: Sendable { let label: String; let confidence: Float; let accepted: Bool }
    private(set) nonisolated(unsafe) var lastPeek: Peek?

    init(model: MLModel, labels: [String], confidenceThreshold: Float = 0.6) {
        self.model = model
        self.labels = labels
        self.confidenceThreshold = confidenceThreshold
    }

    func recognize(_ window: SignSegmenter.Window) async -> RecognitionResult? {
        guard let input = FeatureEncoder.encode(window) else { return nil }
        do {
            let output = try await model.prediction(from: input)
            guard let (label, confidence) = Self.topLabel(from: output, labels: labels) else {
                lastPeek = nil
                return nil
            }
            let accepted = confidence >= confidenceThreshold
            lastPeek = Peek(label: label, confidence: confidence, accepted: accepted)
            guard accepted else { return nil }
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
