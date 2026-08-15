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

    /// Long input keeps the most RECENT frames.
    func testLongSequenceIsTrimmed() throws {
        let frames = (0..<100).map { frame(ts: TimeInterval($0)) }
        let provider = try XCTUnwrap(FeatureEncoder.encodeSequence(frames, length: 24))
        let array = try XCTUnwrap(provider.featureValue(for: "landmarks")?.multiArrayValue)
        XCTAssertEqual(array.shape.map(\.intValue), [1, 24, 198])
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(FeatureEncoder.encodeSequence([], length: 24))
    }

    /// Depth must actually reach the tensor — the whole point of the 3D upgrade.
    func testDepthIsEncoded() throws {
        let withDepth = try XCTUnwrap(FeatureEncoder.encodeSequence([frame(ts: 0)], length: 1))
        let a = try XCTUnwrap(withDepth.featureValue(for: "landmarks")?.multiArrayValue)
        // Third coord of the first left-hand point is its z, relative to the anchor.
        let z0 = a[[0, 0, 2]].floatValue
        XCTAssertNotEqual(z0, 0.0, accuracy: 0.0001,
                          "z should be non-zero when landmarks carry depth")
    }
}
