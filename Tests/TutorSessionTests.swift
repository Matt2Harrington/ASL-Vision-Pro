import XCTest

/// Controllable frame source so lesson flow can be driven deterministically.
final class MockSignFrameSource: SignFrameSource {
    private var continuation: AsyncStream<SignFrame>.Continuation?
    private(set) var stopped = false

    func signFrames() -> AsyncStream<SignFrame> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func stop() { stopped = true; continuation?.finish() }

    func emit(_ frame: SignFrame) { continuation?.yield(frame) }
}

/// Verifier that always returns a fixed score, so scoring thresholds drive the flow.
final class FixedVerifier: SignVerifying {
    let score: Float
    private(set) var seenTargets: [String] = []

    init(score: Float) { self.score = score }

    func verify(_ window: SignSegmenter.Window, expecting expected: String) async -> SignAttempt? {
        seenTargets.append(expected)
        return SignAttempt(expected: expected, score: score, confusedWith: nil,
                           timestamp: window.frames.last?.timestamp ?? 0)
    }
}

@MainActor
final class TutorSessionTests: XCTestCase {

    private func makeSession(lesson: [String], score: Float)
        -> (TutorSession, MockSignFrameSource, FixedVerifier) {
        let source = MockSignFrameSource()
        let verifier = FixedVerifier(score: score)
        let session = TutorSession(lesson: lesson, source: source, verifier: verifier)
        return (session, source, verifier)
    }

    func testStartsOnFirstLessonItem() {
        let (session, _, _) = makeSession(lesson: ["HELLO", "PLEASE"], score: 0.9)
        XCTAssertEqual(session.currentTarget, "HELLO")
        XCTAssertEqual(session.attemptCount, 0)
        XCTAssertEqual(session.correctCount, 0)
    }

    func testSkipAdvancesWithoutScoring() {
        let (session, _, _) = makeSession(lesson: ["HELLO", "PLEASE"], score: 0.9)
        session.skip()
        XCTAssertEqual(session.currentTarget, "PLEASE")
        XCTAssertEqual(session.attemptCount, 0, "skipping must not count as an attempt")
    }

    func testSkippingPastTheEndFinishesLesson() {
        let (session, _, _) = makeSession(lesson: ["HELLO"], score: 0.9)
        session.skip()
        XCTAssertNil(session.currentTarget)
    }

    func testProgressTracksPositionInLesson() {
        let (session, _, _) = makeSession(lesson: ["A", "B", "C", "D"], score: 0.9)
        XCTAssertEqual(session.progress, 0.0, accuracy: 0.001)
        session.skip()
        XCTAssertEqual(session.progress, 0.25, accuracy: 0.001)
        session.skip()
        XCTAssertEqual(session.progress, 0.5, accuracy: 0.001)
    }

    func testAccuracyIsZeroBeforeAnyAttempt() {
        let (session, _, _) = makeSession(lesson: ["HELLO"], score: 0.9)
        XCTAssertEqual(session.accuracy, 0)
    }

    func testEmptyLessonHasNoTargetAndSafeProgress() {
        let (session, _, _) = makeSession(lesson: [], score: 0.9)
        XCTAssertNil(session.currentTarget)
        XCTAssertEqual(session.progress, 0, "must not divide by zero on an empty lesson")
    }

    func testStopReleasesTheSource() {
        let (session, source, _) = makeSession(lesson: ["HELLO"], score: 0.9)
        session.start()
        session.stop()
        XCTAssertTrue(source.stopped, "stopping the session must release the frame source")
        XCTAssertFalse(session.isRunning)
    }

    func testStartIsIdempotent() {
        let (session, _, _) = makeSession(lesson: ["HELLO"], score: 0.9)
        session.start()
        session.start()
        XCTAssertTrue(session.isRunning)
        session.stop()
    }
}
