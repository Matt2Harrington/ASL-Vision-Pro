import Foundation
import Observation
import OSLog

/// Direction 4 — records labeled landmark sequences for training.
///
/// This solves the bottleneck blocking every other direction: there is no ASL dataset in the
/// exact form our model consumes. Because the app prompts for a specific sign, recordings are
/// **automatically labeled** — no annotation pass.
///
/// Critically, it records through the *same* `FeatureEncoder` used at inference, so the
/// train/inference parity problem (MODEL_PLAN §2 — the failure mode that silently destroys
/// accuracy) cannot occur by construction.
///
/// Exports newline-delimited JSON that `training/import_recordings.py` converts to the .npz
/// the trainer expects.
@MainActor
@Observable
final class DataCollector {
    private(set) var currentPrompt: String?
    private(set) var isRecording = false
    private(set) var clipsRecorded = 0
    /// Clips captured per gloss this session, so you can see coverage as you go.
    private(set) var counts: [String: Int] = [:]

    private let log = Logger(subsystem: "ASLVisionPro", category: "DataCollector")
    private let source: SignFrameSource
    private let prompts: [String]
    /// Identifies the person signing — training splits by signer, so this must be recorded.
    private let signerID: String
    private var promptIndex = 0

    private var buffer: [SignFrame] = []
    private var captureTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    /// Seconds of landmarks captured per clip. Long enough for a full sign with margin.
    /// Injectable so tests don't have to wait out a real recording.
    private let clipDuration: TimeInterval
    /// Where clips are appended. Injectable so tests write to a temp file instead of the
    /// user's Documents directory.
    let outputURL: URL

    var progress: Double {
        prompts.isEmpty ? 0 : Double(promptIndex) / Double(prompts.count)
    }

    init(prompts: [String],
         source: SignFrameSource,
         signerID: String,
         outputURL: URL = DataCollector.recordingsURL(),
         clipDuration: TimeInterval = 2.0) {
        self.prompts = prompts
        self.source = source
        self.signerID = signerID
        self.outputURL = outputURL
        self.clipDuration = clipDuration
        self.currentPrompt = prompts.first
    }

    func start() {
        guard streamTask == nil else { return }
        streamTask = Task {
            for await frame in source.signFrames() {
                if Task.isCancelled { break }
                guard isRecording else { continue }
                buffer.append(frame)
            }
        }
    }

    func stop() {
        streamTask?.cancel(); streamTask = nil
        captureTask?.cancel(); captureTask = nil
        source.stop()
        isRecording = false
    }

    /// Record one clip for the current prompt, then advance.
    func recordClip() {
        guard !isRecording, let gloss = currentPrompt else { return }
        buffer.removeAll()
        isRecording = true

        captureTask = Task {
            try? await Task.sleep(for: .seconds(clipDuration))
            isRecording = false
            finishClip(gloss: gloss)
        }
    }

    /// Skip the current prompt without recording.
    func skip() { advance() }

    /// A clip must contain at least one full model window, or it can't be encoded.
    static func isClipLongEnough(_ frames: [SignFrame]) -> Bool {
        frames.count >= FeatureEncoder.sequenceLength
    }

    private func finishClip(gloss: String) {
        let frames = buffer
        buffer.removeAll()
        guard Self.isClipLongEnough(frames) else {
            log.notice("Clip for \(gloss) too short (\(frames.count) frames) — discarded.")
            return
        }
        do {
            try Self.appendRecording(gloss: gloss, signerID: signerID,
                                     frames: frames, to: outputURL)
            clipsRecorded += 1
            counts[gloss, default: 0] += 1
            advance()
        } catch {
            log.error("Failed to write clip: \(error.localizedDescription)")
        }
    }

    private func advance() {
        promptIndex += 1
        currentPrompt = promptIndex < prompts.count ? prompts[promptIndex] : nil
        if currentPrompt == nil { stop() }
    }

    // MARK: - Export

    /// One JSON object per line: {gloss, signer, features: [[Float]]}.
    /// Features are produced by `FeatureEncoder`, guaranteeing parity with inference.
    static func appendRecording(gloss: String, signerID: String,
                                frames: [SignFrame], to url: URL) throws {
        let window = SignSegmenter.Window(frames: frames)
        guard let matrix = FeatureEncoder.encodeMatrix(window) else {
            throw CollectorError.encodingFailed
        }
        let record = Recording(gloss: gloss, signer: signerID, features: matrix)
        let data = try JSONEncoder().encode(record)

        let handle: FileHandle
        if FileManager.default.fileExists(atPath: url.path) {
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
    }

    /// Written to Documents so it's reachable via the Files app / device container.
    /// `nonisolated` because it touches no actor state and is used as a default argument,
    /// which Swift evaluates outside the main actor.
    nonisolated static func recordingsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings.jsonl")
    }

    struct Recording: Codable {
        let gloss: String
        let signer: String
        let features: [[Float]]   // [sequenceLength][featuresPerFrame]
    }

    enum CollectorError: Error { case encodingFailed }
}
