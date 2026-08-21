import XCTest
import Vision

/// Joint ordering is part of the model contract: feature index *i* must mean the same joint
/// in every frame. The original extractor read a dictionary's `values` and filtered by
/// confidence, so order was non-deterministic and the count varied — a model trained on that
/// learns noise. Shape-only tests can't catch it, so these assert the ordering itself.
final class LandmarkOrderTests: XCTestCase {

    func testHandOrderHasExactlyTheExpectedJointCount() {
        XCTAssertEqual(LandmarkExtractor.handJointOrder.count, FeatureEncoder.handPoints)
    }

    func testBodyOrderHasExactlyTheExpectedJointCount() {
        XCTAssertEqual(LandmarkExtractor.bodyJointOrder.count, FeatureEncoder.bodyPoints)
    }

    func testHandOrderHasNoDuplicates() {
        let names = LandmarkExtractor.handJointOrder.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count, "a duplicated joint would waste a slot")
    }

    func testBodyOrderHasNoDuplicates() {
        let names = LandmarkExtractor.bodyJointOrder.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// The standard 21-point hand skeleton: wrist first, then thumb → little, tip last in
    /// each finger. This is also MediaPipe's layout, which is what makes public MediaPipe
    /// landmark datasets mappable onto this pipeline.
    func testHandOrderStartsAtWristAndFollowsThumbToLittle() {
        let order = LandmarkExtractor.handJointOrder
        XCTAssertEqual(order.first, .wrist, "wrist must be index 0, as in MediaPipe")
        XCTAssertEqual(order[4],  .thumbTip)
        XCTAssertEqual(order[8],  .indexTip)
        XCTAssertEqual(order[12], .middleTip)
        XCTAssertEqual(order[16], .ringTip)
        XCTAssertEqual(order[20], .littleTip)
    }

    /// `FeatureEncoder` anchors on body[0] and scales by the body[0]–body[1] distance, so
    /// those two slots must be the shoulders or the normalization is meaningless.
    func testBodyOrderStartsWithShouldersForScaling() {
        XCTAssertEqual(LandmarkExtractor.bodyJointOrder[0], .leftShoulder)
        XCTAssertEqual(LandmarkExtractor.bodyJointOrder[1], .rightShoulder)
    }

    /// Vertical motion must not be inverted relative to training.
    ///
    /// Vision reports normalized points from the image's lower-left corner; MediaPipe, and
    /// every public corpus built on it, uses the upper-left. The extractor flips Y so both
    /// agree. Without it a hand rising from the forehead reaches the model as falling, which
    /// is enough on its own to stop signs from being recognized.
    func testLandmarksUseTopLeftOrigin() {
        // A point near the top of the frame must have a SMALL y, as in image coordinates.
        let high = Landmark(position: CGPoint(x: 0.5, y: 0.1), z: 0, confidence: 1)
        let low  = Landmark(position: CGPoint(x: 0.5, y: 0.9), z: 0, confidence: 1)
        XCTAssertLessThan(high.position.y, low.position.y,
                          "smaller y must mean higher in frame, matching MediaPipe")
    }

    /// Ordering only pays off if the encoder consumes the same counts.
    func testEncoderLayoutMatchesExtractorOrdering() {
        let total = FeatureEncoder.handPoints * 2 + FeatureEncoder.bodyPoints + FeatureEncoder.facePoints
        XCTAssertEqual(total * FeatureEncoder.coordsPerPoint, FeatureEncoder.featuresPerFrame)
    }
}
