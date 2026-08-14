import CoreML
import Foundation

/// Converts a segmented window of `SignFrame`s into the fixed-shape tensor the Core ML
/// model expects. This normalization is the contract between training and inference —
/// **the exact same encoding must be used when generating the training set** (see
/// MODEL_PLAN.md §4 and config/feature_spec.json). Any mismatch silently destroys accuracy.
///
/// These constants MUST match config/feature_spec.json (the shared source of truth read by
/// the Python trainer). If you change one, change both.
enum FeatureEncoder {
    static let sequenceLength = 24                 // feature_spec: sequence_length
    static let handPoints = 21                     // feature_spec: points.left_hand / right_hand
    static let bodyPoints = 8                      // feature_spec: points.body
    static let facePoints = 16                     // feature_spec: points.face
    static var featuresPerFrame: Int { (handPoints * 2 + bodyPoints + facePoints) * 2 } // = 132

    /// Fixed-window encoder for the isolated-sign classifier (Levels 1–2). Produces
    /// `"landmarks"` of shape [1, sequenceLength, featuresPerFrame].
    static func encode(_ window: SignSegmenter.Window) -> MLFeatureProvider? {
        encodeSequence(window.frames, length: sequenceLength)
    }

    /// Variable-length encoder for the continuous CTC recognizer (Level 3). Pads/trims to
    /// `length` and produces `"landmarks"` of shape [1, length, featuresPerFrame]. Sharing
    /// this with `encode` guarantees the two recognizers use identical normalization.
    static func encodeSequence(_ frames: [SignFrame], length: Int) -> MLFeatureProvider? {
        guard !frames.isEmpty else { return nil }
        let seq = padOrTrim(frames, to: length)
        guard let array = try? MLMultiArray(shape: [1,
                                                    NSNumber(value: length),
                                                    NSNumber(value: featuresPerFrame)],
                                            dataType: .float32) else { return nil }

        for (t, frame) in seq.enumerated() {
            let flat = flatten(frame)
            for (i, value) in flat.enumerated() {
                array[[0, NSNumber(value: t), NSNumber(value: i)]] = NSNumber(value: value)
            }
        }
        return try? MLDictionaryFeatureProvider(dictionary: ["landmarks": MLFeatureValue(multiArray: array)])
    }

    /// Flatten one frame into a normalized [x0,y0,x1,y1,...] vector, centered on the torso
    /// and scaled by shoulder width so recognition is invariant to signer distance/position.
    private static func flatten(_ frame: SignFrame) -> [Float] {
        let anchor = frame.body.first?.position ?? CGPoint(x: 0.5, y: 0.5)
        let scale = shoulderScale(frame)

        func encode(_ points: [Landmark], count: Int) -> [Float] {
            var out = [Float](repeating: 0, count: count * 2)
            for (i, lm) in points.prefix(count).enumerated() {
                out[i * 2]     = Float((lm.position.x - anchor.x) / scale)
                out[i * 2 + 1] = Float((lm.position.y - anchor.y) / scale)
            }
            return out
        }

        return encode(frame.leftHand, count: handPoints)
             + encode(frame.rightHand, count: handPoints)
             + encode(frame.body, count: bodyPoints)
             + encode(frame.face, count: facePoints)
    }

    private static func shoulderScale(_ frame: SignFrame) -> CGFloat {
        guard frame.body.count >= 2 else { return 1 }
        let dx = frame.body[0].position.x - frame.body[1].position.x
        let dy = frame.body[0].position.y - frame.body[1].position.y
        return max(0.05, sqrt(dx * dx + dy * dy))   // guard against divide-by-zero
    }

    private static func padOrTrim(_ frames: [SignFrame], to length: Int) -> [SignFrame] {
        if frames.count == length { return frames }
        if frames.count > length { return Array(frames.suffix(length)) }
        // Left-pad by repeating the first frame so timing stays right-aligned to "now".
        return Array(repeating: frames.first!, count: length - frames.count) + frames
    }
}
