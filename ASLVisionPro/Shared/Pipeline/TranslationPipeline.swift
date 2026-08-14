import CoreVideo
import Foundation
import Observation
import OSLog

/// Orchestrates the full on-device pipeline and publishes live captions to the UI.
///
///   camera → landmarks → segmentation → recognition → caption assembly
///
/// `@Observable` so SwiftUI views update as captions stream in. Everything runs on-device;
/// no footage or landmarks leave the headset (ARCHITECTURE.md §7).
@MainActor
@Observable
final class TranslationPipeline {
    /// The live, revisable caption shown to the user.
    private(set) var caption: String = ""
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

    /// Most recent landmarks, for the Phase 1 debug overlay.
    private(set) var latestFrame: SignFrame?

    private var runTask: Task<Void, Never>?
    private let startTime = Date()

    init(source: FrameSource, recognizer: SignRecognizing = StubSignRecognizer()) {
        self.source = source
        self.recognizer = recognizer
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
            guard let result = await recognizer.recognize(window) else { continue }

            history.append(result)
            caption = assembler.append(result)
        }
        isRunning = false
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
