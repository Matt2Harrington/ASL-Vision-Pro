import AVFoundation
import Foundation
import Observation
import OSLog
import Speech

/// Live on-device speech-to-text — the "hearing person speaks, wearer sees it" direction.
///
/// This is the inverse of sign recognition and, unlike it, a **solved problem**: no camera,
/// no entitlement, no trained model. visionOS/iOS 26 provide `SpeechAnalyzer` +
/// `SpeechTranscriber`, which run fully on-device and stream low-latency partial results —
/// so captions appear as the person is still talking.
///
/// Emits `volatile` (in-progress, revisable) text separately from `finalized` text, which is
/// what makes captions feel live rather than arriving in blocks.
/// Requires OS 26 for SpeechAnalyzer/SpeechTranscriber; callers must gate on availability.
@available(visionOS 26.0, iOS 26.0, macOS 26.0, *)
@MainActor
@Observable
final class SpeechListener {
    /// Text confirmed by the recognizer; append-only.
    private(set) var finalizedText: String = ""
    /// Best-guess text for speech still in progress; replaced as it firms up.
    private(set) var volatileText: String = ""
    private(set) var isListening = false
    private(set) var errorMessage: String?

    /// What the UI should show: settled text plus the live tail.
    var displayText: String {
        [finalizedText, volatileText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private let log = Logger(subsystem: "ASLVisionPro", category: "Speech")
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?

    func start() async {
        guard !isListening else { return }
        errorMessage = nil

        guard await requestPermission() else {
            errorMessage = "Microphone access denied."
            return
        }

        do {
            try await configure()
            isListening = true
        } catch {
            log.error("Speech start failed: \(error.localizedDescription)")
            errorMessage = "Could not start listening."
            stop()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        inputBuilder?.finish()
        inputBuilder = nil
        recognizerTask?.cancel()
        recognizerTask = nil
        analyzer = nil
        transcriber = nil
        isListening = false
    }

    func clear() {
        finalizedText = ""
        volatileText = ""
    }

    // MARK: - Setup

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func configure() throws {
        let locale = Locale.current
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Consume streaming results; volatile text is revisable, finalized text is not.
        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedText = [self.finalizedText, text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                }
            } catch {
                self?.log.error("Transcription stream ended: \(error.localizedDescription)")
            }
        }

        // Feed microphone audio into the analyzer.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = continuation

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }

        engine.prepare()
        try engine.start()

        Task { [weak self] in
            try? await self?.analyzer?.start(inputSequence: stream)
        }
    }
}
