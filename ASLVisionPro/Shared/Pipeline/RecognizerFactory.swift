import CoreML
import Foundation
import OSLog

/// Single place where the app decides which recognizer to run — shared by BOTH the visionOS
/// and iOS targets, so a model drop-in is one edit, not one per platform.
///
/// Load order:
///   1. `SignModel.mlpackage`     → isolated-sign / fingerspelling classifier (Levels 1–2)
///   2. `SignCTCModel.mlpackage`  → continuous CTC recognizer (Level 3)
///   3. neither present           → `StubSignRecognizer` (pipeline runs, emits placeholders)
///
/// To enable a real model: add the compiled model to BOTH app targets and ship its labels
/// as `labels.json` (classifier) or `vocab.json` (CTC) in the bundle. No code change needed.
enum RecognizerFactory {
    private static let log = Logger(subsystem: "ASLVisionPro", category: "RecognizerFactory")

    /// Which level to prefer when more than one model is bundled.
    enum Mode {
        case isolated     // Levels 1–2: fingerspelling + isolated signs
        case continuous   // Level 3: CTC continuous recognition
        case automatic    // isolated if available, else continuous, else stub
    }

    /// True when a trained model is actually bundled.
    ///
    /// The UI uses this to state plainly that feedback is simulated. Without it the stubs are
    /// indistinguishable from real recognition — the tutor cycles through encouraging scores
    /// on a fixed rotation regardless of what is signed, which is convincing and false. For a
    /// tool people might use to judge their own signing, that is the worst kind of wrong.
    static var hasBundledModel: Bool {
        Bundle.main.url(forResource: "SignModel", withExtension: "mlmodelc") != nil
    }

    static func makeRecognizer(mode: Mode = .automatic) -> SignRecognizing {
        switch mode {
        case .isolated:
            return makeIsolated() ?? fallback()
        case .continuous:
            return makeContinuous() ?? fallback()
        case .automatic:
            return makeIsolated() ?? makeContinuous() ?? fallback()
        }
    }

    // MARK: - Levels 1–2

    private static func makeIsolated() -> SignRecognizing? {
        guard let model = loadModel(named: "SignModel"),
              let labels = loadStrings(resource: "labels") else { return nil }
        log.info("Using CoreMLSignRecognizer with \(labels.count) classes.")
        return CoreMLSignRecognizer(model: model, labels: labels)
    }

    // MARK: - Level 3

    private static func makeContinuous() -> SignRecognizing? {
        guard let model = loadModel(named: "SignCTCModel"),
              let vocab = loadStrings(resource: "vocab") else { return nil }
        log.info("Using ContinuousSignRecognizer with \(vocab.count) vocab entries.")
        return ContinuousSignRecognizer(model: model, vocab: vocab)
    }

    // MARK: - Tutor verification

    /// Verifier for tutor mode. Reuses the same bundled classifier as recognition — the
    /// tutor just reads the probability of the *expected* class instead of the argmax.
    /// Without this, `CoreMLSignVerifier` would be unreachable and tutor mode would stay on
    /// the stub even after a model shipped.
    static func makeVerifier() -> SignVerifying {
        guard let model = loadModel(named: "SignModel"),
              let labels = loadStrings(resource: "labels") else {
            log.notice("No bundled model found — falling back to StubSignVerifier.")
            return StubSignVerifier()
        }
        log.info("Using CoreMLSignVerifier with \(labels.count) classes.")
        return CoreMLSignVerifier(model: model, labels: labels)
    }

    // MARK: - Fallback

    private static func fallback() -> SignRecognizing {
        log.notice("No bundled model found — falling back to StubSignRecognizer.")
        return StubSignRecognizer()
    }

    // MARK: - Bundle loading

    /// Looks for the Xcode-compiled `.mlmodelc` produced from a bundled `.mlpackage`.
    private static func loadModel(named name: String) -> MLModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { return nil }
        do {
            return try MLModel(contentsOf: url)
        } catch {
            log.error("Failed to load \(name): \(error.localizedDescription)")
            return nil
        }
    }

    private static func loadStrings(resource: String) -> [String]? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return list
    }
}
