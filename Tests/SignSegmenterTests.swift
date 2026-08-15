import XCTest

/// The segmenter decides *when* the model runs, so its windowing, stride, and activity gate
/// directly control both recognition quality and battery cost. It had no coverage.
final class SignSegmenterTests: XCTestCase {

    private func frame(_ ts: TimeInterval, hands: Bool = true) -> SignFrame {
        let lm = [Landmark(position: .zero, z: 0, confidence: 1)]
        return SignFrame(timestamp: ts,
                         leftHand: hands ? lm : [],
                         rightHand: [],
                         body: lm,
                         face: [])
    }

    /// No window until the buffer is full — a short burst must not be classified.
    func testNoWindowBeforeBufferFills() {
        let s = SignSegmenter(windowSize: 10, stride: 5)
        for i in 0..<9 {
            XCTAssertNil(s.accept(frame(TimeInterval(i))), "emitted at frame \(i)")
        }
        XCTAssertNotNil(s.accept(frame(9)), "should emit once the buffer is full")
    }

    func testWindowHasExactlyWindowSizeFrames() {
        let s = SignSegmenter(windowSize: 10, stride: 5)
        var window: SignSegmenter.Window?
        for i in 0..<10 { window = s.accept(frame(TimeInterval(i))) ?? window }
        XCTAssertEqual(window?.frames.count, 10)
    }

    /// After emitting, the next window must wait `stride` frames — this is what keeps
    /// inference off the Neural Engine on every single frame.
    func testStrideThrottlesSubsequentWindows() {
        let s = SignSegmenter(windowSize: 10, stride: 5)
        for i in 0..<10 { _ = s.accept(frame(TimeInterval(i))) }   // first emit

        for i in 10..<14 {
            XCTAssertNil(s.accept(frame(TimeInterval(i))), "emitted early at frame \(i)")
        }
        XCTAssertNotNil(s.accept(frame(14)), "should emit again after stride frames")
    }

    /// Windows slide: the newest frame must be present, the oldest evicted.
    func testWindowSlidesToMostRecentFrames() {
        let s = SignSegmenter(windowSize: 5, stride: 1)
        var last: SignSegmenter.Window?
        for i in 0..<8 { last = s.accept(frame(TimeInterval(i))) ?? last }
        XCTAssertEqual(last?.frames.first?.timestamp, 3)
        XCTAssertEqual(last?.frames.last?.timestamp, 7)
    }

    /// Idle hands must not burn inference cycles.
    func testIdleHandsAreGated() {
        let s = SignSegmenter(windowSize: 10, stride: 1)
        for i in 0..<20 {
            XCTAssertNil(s.accept(frame(TimeInterval(i), hands: false)),
                         "classified a rest pose at frame \(i)")
        }
    }

    /// The gate is a ratio, so a few dropped-tracking frames shouldn't suppress a real sign.
    func testMostlyActiveWindowStillEmits() {
        let s = SignSegmenter(windowSize: 10, stride: 1)
        var emitted = false
        for i in 0..<10 {
            // 8 of 10 frames tracked — above the 0.6 threshold.
            let tracked = !(i == 3 || i == 7)
            if s.accept(frame(TimeInterval(i), hands: tracked)) != nil { emitted = true }
        }
        XCTAssertTrue(emitted, "a mostly-tracked window should still be classified")
    }

    /// Below the ratio threshold, nothing is emitted.
    func testMostlyIdleWindowIsSuppressed() {
        let s = SignSegmenter(windowSize: 10, stride: 1)
        var emitted = false
        for i in 0..<10 {
            let tracked = (i < 4)   // 4 of 10 — below threshold
            if s.accept(frame(TimeInterval(i), hands: tracked)) != nil { emitted = true }
        }
        XCTAssertFalse(emitted)
    }

    /// Signing that resumes after a pause should be picked up promptly rather than waiting
    /// out another full stride.
    func testResumesPromptlyAfterIdlePeriod() {
        let s = SignSegmenter(windowSize: 5, stride: 3)
        for i in 0..<20 { _ = s.accept(frame(TimeInterval(i), hands: false)) }
        var emitted = false
        for i in 20..<25 {
            if s.accept(frame(TimeInterval(i), hands: true)) != nil { emitted = true }
        }
        XCTAssertTrue(emitted, "should emit once the buffer refills with active frames")
    }
}
