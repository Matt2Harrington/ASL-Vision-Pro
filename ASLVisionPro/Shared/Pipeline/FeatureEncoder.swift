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
    static let coordsPerPoint = 3                  // feature_spec: coords_per_point (x, y, z)
    /// feature_spec: hands_only.
    ///
    /// MediaPipe and Apple Vision agree on the 21-point hand skeleton but not on face or body:
    /// 468 face points versus ~76, and different pose joints. Training on those regions with
    /// public MediaPipe data teaches patterns that are noise on device. Their slots stay in the
    /// tensor (so the model shape is unchanged) but carry zeros on both sides.
    static let handsOnly = true
    /// feature_spec: uses_depth.
    ///
    /// Vision gives no depth on the camera path, so models are trained with z zeroed. visionOS
    /// hand tracking *does* supply real depth — feeding it to a model trained on zeros would be
    /// a silent mismatch, so depth is zeroed here until a depth-trained model ships.
    static let usesDepth = false
    static var featuresPerFrame: Int { (handPoints * 2 + bodyPoints + facePoints) * coordsPerPoint } // = 198

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

    /// Same normalization as `encode`, returned as a plain `[sequenceLength][featuresPerFrame]`
    /// matrix instead of an MLMultiArray. Used by `DataCollector` to export training clips —
    /// going through this shared path is what guarantees the recorded features are byte-for-byte
    /// what the model will see at inference (MODEL_PLAN §2).
    static func encodeMatrix(_ window: SignSegmenter.Window) -> [[Float]]? {
        guard !window.frames.isEmpty else { return nil }
        return padOrTrim(window.frames, to: sequenceLength).map(flatten)
    }

    /// Flatten one frame into a normalized [x0,y0,z0,x1,y1,z1,...] vector, centered on the
    /// torso and scaled by shoulder width so recognition is invariant to signer
    /// distance/position. `z` is 0 for 2D sources and a real depth for hand tracking.
    private static func flatten(_ frame: SignFrame) -> [Float] {
        var out = [Float](repeating: 0, count: featuresPerFrame)

        if handsOnly {
            // Each hand is normalized against its own wrist and span. That removes any
            // dependence on detecting the torso — which often fails on a phone held close,
            // where only hands are in frame — and it is computed identically from MediaPipe
            // and Vision landmarks, since their hand topology matches.
            writeHand(frame.leftHand,  into: &out, at: 0)
            writeHand(frame.rightHand, into: &out, at: handPoints * coordsPerPoint)
            return out
        }

        let anchor = frame.body.first?.position ?? CGPoint(x: 0.5, y: 0.5)
        let anchorZ = frame.body.first?.z ?? 0
        let scale = shoulderScale(frame)

        func encode(_ points: [Landmark], count: Int) -> [Float] {
            var seg = [Float](repeating: 0, count: count * coordsPerPoint)
            for (i, lm) in points.prefix(count).enumerated() {
                seg[i * coordsPerPoint]     = Float((lm.position.x - anchor.x) / scale)
                seg[i * coordsPerPoint + 1] = Float((lm.position.y - anchor.y) / scale)
                seg[i * coordsPerPoint + 2] = usesDepth ? (lm.z - anchorZ) / Float(scale) : 0
            }
            return seg
        }

        return encode(frame.leftHand, count: handPoints)
             + encode(frame.rightHand, count: handPoints)
             + encode(frame.body, count: bodyPoints)
             + encode(frame.face, count: facePoints)
    }

    /// Write one hand, centred on its wrist (joint 0) and scaled by the wrist-to-middle-MCP
    /// distance (joint 9) — a stable proxy for hand size, so recognition doesn't depend on how
    /// close the hand is to the camera. An undetected hand leaves zeros.
    private static func writeHand(_ points: [Landmark], into out: inout [Float], at offset: Int) {
        guard points.count >= handPoints, points[0].confidence > 0 else { return }
        let wrist = points[0]
        let mid = points[9]
        let dx = mid.position.x - wrist.position.x
        let dy = mid.position.y - wrist.position.y
        let span = max(0.02, sqrt(dx * dx + dy * dy))

        for i in 0..<handPoints {
            let lm = points[i]
            let base = offset + i * coordsPerPoint
            out[base]     = Float((lm.position.x - wrist.position.x) / span)
            out[base + 1] = Float((lm.position.y - wrist.position.y) / span)
            out[base + 2] = usesDepth ? (lm.z - wrist.z) / Float(span) : 0
        }
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
