import XCTest
import CoreML

/// Guards the train/inference feature contract (config/feature_spec.json). A silent drift
/// here destroys model accuracy in a way that is very hard to debug, so the shape and layout
/// are asserted explicitly.
final class FeatureEncoderTests: XCTestCase {

    private func landmarks(_ n: Int, z: Float = 0) -> [Landmark] {
        (0..<n).map { i in
            Landmark(position: CGPoint(x: Double(i) / 100.0, y: Double(i) / 100.0),
                     z: z, confidence: 1.0)
        }
    }

    private func frame(ts: TimeInterval) -> SignFrame {
        SignFrame(timestamp: ts,
                  leftHand: landmarks(21, z: 0.1),
                  rightHand: landmarks(21, z: 0.2),
                  body: landmarks(8),
                  face: landmarks(16))
    }

    /// 198 = (21 + 21 + 8 + 16) points x 3 coords. Must match feature_spec.json.
    func testFeaturesPerFrameMatchesSpec() {
        XCTAssertEqual(FeatureEncoder.coordsPerPoint, 3)
        XCTAssertEqual(FeatureEncoder.featuresPerFrame, 198)
    }

    func testEncodedShapeIsBatchSeqFeatures() throws {
        let frames = (0..<24).map { frame(ts: TimeInterval($0)) }
        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence(frames, length: 24))
        let array = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)

        XCTAssertEqual(array.shape.map(\.intValue), [1, 24, 198])
    }

    /// Short input must left-pad (timing stays right-aligned to "now"), not fail.
    func testShortSequenceIsPadded() throws {
        let frames = (0..<5).map { frame(ts: TimeInterval($0)) }
        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence(frames, length: 24))
        let array = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        XCTAssertEqual(array.shape.map(\.intValue), [1, 24, 198])
    }

    /// A longer capture is RESAMPLED across its whole span, not truncated to the tail.
    ///
    /// This mirrors how training clips were time-normalized — each is a whole sign stretched
    /// to fill the window — so the model sees signs at the temporal scale it learned. Keeping
    /// only the most recent frames would feed it the end of a sign and drop the start.
    func testLongSequenceIsResampledNotTruncated() throws {
        let frames = (0..<100).map { frame(ts: TimeInterval($0)) }
        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence(frames, length: 24))
        let array = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        XCTAssertEqual(array.shape.map(\.intValue), [1, 24, 198])
    }

    /// The resampling must span the entire capture: first output frame from the first input,
    /// last from the last. Truncation would make both come from the tail.
    func testResamplingCoversTheWholeSpan() {
        let frames = (0..<100).map { frame(ts: TimeInterval($0)) }
        let picked = FeatureEncoder.resampleForTesting(frames, to: 24)
        XCTAssertEqual(picked.count, 24)
        XCTAssertEqual(picked.first?.timestamp, 0, "must start at the beginning of the sign")
        XCTAssertEqual(picked.last?.timestamp, 99, "must end at the most recent frame")
    }

    /// A single frame is valid input and must fill the window rather than crash.
    func testSingleFrameFillsWindow() {
        let picked = FeatureEncoder.resampleForTesting([frame(ts: 5)], to: 24)
        XCTAssertEqual(picked.count, 24)
        XCTAssertTrue(picked.allSatisfy { $0.timestamp == 5 })
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(FeatureEncoder.encodeSequence([], length: 24))
    }

    /// Depth is deliberately zeroed. Vision supplies no z on the camera path, so models are
    /// trained with depth zeroed — and visionOS hand tracking, which does supply real depth,
    /// must be encoded the same way or it feeds the model a channel it never saw in training.
    func testDepthIsZeroedToMatchTraining() throws {
        XCTAssertFalse(FeatureEncoder.usesDepth,
                       "flip this only alongside a model actually trained with depth")

        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence([frame(ts: 0)], length: 1))
        let a = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        for point in 0..<FeatureEncoder.handPoints {
            let z = a[[0, 0, NSNumber(value: point * FeatureEncoder.coordsPerPoint + 2)]].floatValue
            XCTAssertEqual(z, 0, accuracy: 0.0001, "z must be zero at point \(point)")
        }
    }

    /// Hands-only: face and body slots stay in the tensor (so the shape is unchanged) but must
    /// carry zeros, because MediaPipe and Vision disagree on those topologies.
    func testFaceAndBodySlotsAreZeroedWhenHandsOnly() throws {
        try XCTSkipUnless(FeatureEncoder.handsOnly)

        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence([frame(ts: 0)], length: 1))
        let a = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        let handFeatures = FeatureEncoder.handPoints * 2 * FeatureEncoder.coordsPerPoint
        for i in handFeatures..<FeatureEncoder.featuresPerFrame {
            XCTAssertEqual(a[[0, 0, NSNumber(value: i)]].floatValue, 0, accuracy: 0.0001,
                           "feature \(i) should be zero outside the hand region")
        }
    }

    /// Hand landmarks must still be written, or hands-only would encode nothing at all.
    func testHandFeaturesAreNonZero() throws {
        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence([frame(ts: 0)], length: 1))
        let a = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        let handFeatures = FeatureEncoder.handPoints * 2 * FeatureEncoder.coordsPerPoint
        let any = (0..<handFeatures).contains { a[[0, 0, NSNumber(value: $0)]].floatValue != 0 }
        XCTAssertTrue(any, "hand region encoded all zeros")
    }
}
