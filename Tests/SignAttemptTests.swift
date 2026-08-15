import XCTest

/// Locks the tutor's scoring thresholds — these drive what a learner is told, so the
/// boundaries should not drift silently.
final class SignAttemptTests: XCTestCase {

    private func attempt(_ score: Float, confusedWith: String? = nil) -> SignAttempt {
        SignAttempt(expected: "HELLO", score: score, confusedWith: confusedWith, timestamp: 0)
    }

    func testFeedbackTiers() {
        XCTAssertEqual(attempt(0.95).feedback, .excellent)
        XCTAssertEqual(attempt(0.85).feedback, .excellent)   // boundary
        XCTAssertEqual(attempt(0.70).feedback, .good)
        XCTAssertEqual(attempt(0.60).feedback, .good)        // boundary
        XCTAssertEqual(attempt(0.45).feedback, .close)
        XCTAssertEqual(attempt(0.35).feedback, .close)       // boundary
        XCTAssertEqual(attempt(0.10).feedback, .tryAgain)
    }

    /// `isCorrect` must align with the .good threshold — a learner told "Good" should be
    /// credited, and one told "Close" should not.
    func testIsCorrectMatchesGoodThreshold() {
        XCTAssertTrue(attempt(0.60).isCorrect)
        XCTAssertFalse(attempt(0.59).isCorrect)
        XCTAssertTrue(attempt(0.99).isCorrect)
        XCTAssertFalse(attempt(0.0).isCorrect)
    }

    func testConfusionIsReportedOnMiss() {
        let miss = attempt(0.3, confusedWith: "PLEASE")
        XCTAssertFalse(miss.isCorrect)
        XCTAssertEqual(miss.confusedWith, "PLEASE")
    }

    func testFeedbackMessagesAreDistinct() {
        let messages = Set([
            SignAttempt.Feedback.excellent.message,
            SignAttempt.Feedback.good.message,
            SignAttempt.Feedback.close.message,
            SignAttempt.Feedback.tryAgain.message,
        ])
        XCTAssertEqual(messages.count, 4)
    }
}

extension SignAttempt.Feedback: @retroactive Equatable {}
