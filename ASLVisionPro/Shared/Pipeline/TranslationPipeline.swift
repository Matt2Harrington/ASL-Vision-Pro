import CoreVideo
import Foundation
import Observation
import OSLog

/// Orchestrates the full on-device pipeline and publishes live captions to the UI.
///
///   camera → landmarks → segmentation → recognition → glosses → translation
///
/// Two stages, split by what each is good at: the Core ML recognizer *perceives* signs, and
/// an on-device language model turns the resulting glosses into English (ASL grammar is not
/// English word order, so joining glosses gives word salad). Both run locally — no footage
/// or landmarks leave the device, and the language model only ever sees text.
///
/// `@Observable` so SwiftUI views update as captions stream in.
@MainActor
@Observable
final class TranslationPipeline {
    /// Raw recognized glosses, e.g. "ME NAME M-A-T-T". Always shown — it's what the model
    /// actually saw, and stays visible even when translation is unavailable.
    private(set) var caption: String = ""
    /// English translation of the current gloss run, when a language model produced one.
    /// Nil means "no translation" rather than a guess.
    private(set) var translation: String?
    /// True while the language model is working, so the UI can show it's thinking.
    private(set) var isTranslating = false
    /// Rolling history of confirmed results (for a transcript panel / debugging).
    private(set) var history: [RecognitionResult] = []
    /// True while the camera session is delivering frames.
    private(set) var isRunning = false

    private let log = Logger(subsystem: "ASLVisionPro", category: "Pipeline")
    private let source: FrameSource
    private let extractor = LandmarkExtractor()
    private let segmenter = SignSegmenter()
    private let recognizer: SignRecognizing
    private let assembler = CaptionAssembler()
    private let interpreter: GlossInterpreting

    /// Glosses accumulated since the last translation.
    private var pendingGlosses: [String] = []
    private var translateTask: Task<Void, Never>?
    /// How long signing must pause before translating. Translating mid-utterance produces
    /// sentences that are wrong until the phrase finishes.
    private let translationDelay: Duration = .milliseconds(900)

    /// Most recent landmarks, for the Phase 1 debug overlay.
    private(set) var latestFrame: SignFrame?
    /// The recognizer's latest guess, including ones rejected by the confidence gate, so the
    /// UI can explain silence instead of just showing nothing.
    private(set) var lastGuess: CoreMLSignRecognizer.Peek?

    private var runTask: Task<Void, Never>?
    private let startTime = Date()

    init(source: FrameSource,
         recognizer: SignRecognizing = StubSignRecognizer(),
         interpreter: GlossInterpreting = GlossInterpreterFactory.make()) {
        self.source = source
        self.recognizer = recognizer
        self.interpreter = interpreter
    }

    func start() {
        guard runTask == nil else { return }
        isRunning = true
        runTask = Task { await run() }
    }

    func stop() {
        source.stop()
        runTask?.cancel()
        runTask = nil
        translateTask?.cancel()
        translateTask = nil
        isRunning = false
    }

    private func run() async {
        for await captured in source.frames() {
            if Task.isCancelled { break }
            let ts = Date().timeIntervalSince(startTime)

            guard let frame = extractor.extract(from: captured.pixelBuffer,
                                                orientation: captured.orientation,
                                                timestamp: ts) else { continue }
            latestFrame = frame   // raw pixelBuffer is dropped here; only landmarks continue

            guard let window = segmenter.accept(frame) else { continue }
            let result = await recognizer.recognize(window)
            if let coreML = recognizer as? CoreMLSignRecognizer { lastGuess = coreML.lastPeek }
            guard let result else { continue }

            history.append(result)
            caption = assembler.append(result)
            scheduleTranslation(of: result)
        }
        isRunning = false
    }
}

// MARK: - Translation

extension TranslationPipeline {
    /// Collect glosses and translate once signing pauses. Each new sign restarts the timer,
    /// so a phrase is translated as a whole rather than re-translated on every sign.
    private func scheduleTranslation(of result: RecognitionResult) {
        // Continuous recognizers already emit whole phrases; nothing to assemble.
        guard result.kind != .phrase else { return }

        pendingGlosses.append(result.text)
        translateTask?.cancel()
        translateTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.translationDelay)
            guard !Task.isCancelled else { return }
            await self.translatePending()
        }
    }

    private func translatePending() async {
        let glosses = pendingGlosses
        guard glosses.count >= 2 else { return }

        isTranslating = true
        let english = await interpreter.interpret(glosses)
        isTranslating = false

        // Keep the previous translation rather than blanking the line when the model
        // declines — an empty result is not evidence the earlier one was wrong.
        if let english { translation = english }
    }

    /// Live calibration knobs, applied to the Core ML recognizer when present.
    var confidenceThreshold: Float {
        get { (recognizer as? CoreMLSignRecognizer)?.confidenceThreshold ?? 0 }
        set { (recognizer as? CoreMLSignRecognizer)?.confidenceThreshold = newValue }
    }
    var requiredStreak: Int {
        get { (recognizer as? CoreMLSignRecognizer)?.requiredStreak ?? 0 }
        set { (recognizer as? CoreMLSignRecognizer)?.requiredStreak = newValue }
    }
    var isCalibratable: Bool { recognizer is CoreMLSignRecognizer }

    /// Clear the caption and start a fresh utterance.
    func reset() {
        translateTask?.cancel()
        pendingGlosses.removeAll()
        translation = nil
        caption = ""
    }
}

/// Turns a stream of recognized units into readable, revisable caption text.
/// Debounces repeats (a sign spans several windows) and caps the visible line length.
final class CaptionAssembler {
    private var tokens: [String] = []
    private var lastText: String?
    private let maxTokens = 24
    /// True when the last token is a fingerspelled word still being built up, so subsequent
    /// letters extend it (C→CA→CAT) instead of starting new tokens. Any non-letter result
    /// ends the word.
    private var isSpellingWord = false

    func append(_ result: RecognitionResult) -> String {
        // Continuous translation (Level 3) emits a full, revisable phrase each call — the
        // decode of the whole rolling context — so it REPLACES the line rather than appending.
        if result.kind == .phrase {
            tokens = [result.text]
            lastText = result.text
            isSpellingWord = false
            return result.text
        }

        // Levels 1–2: accumulate letters/signs, collapsing duplicates from overlapping windows.
        if result.text != lastText {
            if result.kind == .letter, isSpellingWord, let last = tokens.last {
                tokens[tokens.count - 1] = last + result.text   // extend the fingerspelled word
            } else {
                tokens.append(result.text)
            }
            isSpellingWord = (result.kind == .letter)
            lastText = result.text
        }
        if tokens.count > maxTokens { tokens.removeFirst(tokens.count - maxTokens) }
        return tokens.joined(separator: " ")
    }
}
