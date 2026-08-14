import Foundation
import Observation
import OSLog

/// Drives a practice lesson: presents a target sign, watches the wearer's hands, scores each
/// attempt, and advances. `@Observable` so the tutor UI tracks it directly.
///
/// Uses `HandTrackingSource` (wearer's 3D hands, no entitlement) rather than a camera, so
/// `LandmarkExtractor` is bypassed — ARKit already supplies joints.
@MainActor
@Observable
final class TutorSession {
    /// The sign the learner should attempt right now.
    private(set) var currentTarget: String?
    /// Most recent scored attempt, for feedback UI.
    private(set) var lastAttempt: SignAttempt?
    /// Correct attempts this session.
    private(set) var correctCount = 0
    /// Total scored attempts this session.
    private(set) var attemptCount = 0
    private(set) var isRunning = false
    /// True while we're showing feedback before advancing to the next sign.
    private(set) var isShowingFeedback = false

    private let log = Logger(subsystem: "ASLVisionPro", category: "Tutor")
    private let source: SignFrameSource
    private let verifier: SignVerifying
    private let segmenter = SignSegmenter()
    private var lesson: [String]
    private var index = 0
    private var runTask: Task<Void, Never>?

    /// Cooldown so one sustained attempt isn't scored dozens of times by overlapping windows.
    private var lastScoredAt: TimeInterval = -.greatestFiniteMagnitude
    private let scoreCooldown: TimeInterval = 1.5

    var progress: Double {
        lesson.isEmpty ? 0 : Double(index) / Double(lesson.count)
    }
    var accuracy: Double {
        attemptCount == 0 ? 0 : Double(correctCount) / Double(attemptCount)
    }

    /// `source` is injected so this stays platform-neutral: visionOS passes a
    /// `HandTrackingSource` (3D wearer hands), camera platforms pass a
    /// `CameraSignFrameSource`, and tests pass a mock.
    init(lesson: [String],
         source: SignFrameSource,
         verifier: SignVerifying = StubSignVerifier()) {
        self.lesson = lesson
        self.source = source
        self.verifier = verifier
        self.currentTarget = lesson.first
    }

    func start() {
        guard runTask == nil, !lesson.isEmpty else { return }
        isRunning = true
        runTask = Task { await run() }
    }

    func stop() {
        source.stop()
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    /// Skip the current sign without scoring it.
    func skip() {
        advance()
    }

    private func run() async {
        for await frame in source.signFrames() {
            if Task.isCancelled { break }
            guard let target = currentTarget, !isShowingFeedback else { continue }
            guard let window = segmenter.accept(frame) else { continue }

            // Debounce: one score per attempt, not per overlapping window.
            guard frame.timestamp - lastScoredAt > scoreCooldown else { continue }

            guard let attempt = await verifier.verify(window, expecting: target) else { continue }
            // Ignore weak noise so idle hands don't burn through the lesson.
            guard attempt.score > 0.15 else { continue }

            lastScoredAt = frame.timestamp
            record(attempt)
        }
        isRunning = false
    }

    private func record(_ attempt: SignAttempt) {
        lastAttempt = attempt
        attemptCount += 1
        if attempt.isCorrect {
            correctCount += 1
            isShowingFeedback = true
            // Let the learner see the success before moving on.
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                isShowingFeedback = false
                advance()
            }
        }
    }

    private func advance() {
        index += 1
        lastAttempt = nil
        lastScoredAt = -.greatestFiniteMagnitude
        currentTarget = index < lesson.count ? lesson[index] : nil
        if currentTarget == nil {
            log.info("Lesson complete: \(self.correctCount)/\(self.attemptCount) correct.")
            stop()
        }
    }
}
