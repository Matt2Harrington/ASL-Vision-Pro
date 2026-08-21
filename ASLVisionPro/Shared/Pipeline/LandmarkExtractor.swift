import CoreVideo
import ImageIO
import Vision
import OSLog

/// Phase 1 — turn a camera frame into holistic landmarks for the signer.
///
/// **Joint order is part of the model contract.** Feature index *i* must mean the same joint
/// in every frame, so joints are read by name from an explicit ordered list and missing ones
/// are emitted as zero-confidence placeholders rather than dropped. Reading a dictionary's
/// `values` instead would be non-deterministic (Swift hashes with a per-process seed) and
/// filtering would shift every later joint — either one silently destroys training.
///
/// The hand order below is deliberately the standard 21-point skeleton
/// (wrist, then thumb → little, 4 joints each), which is the same layout MediaPipe uses.
/// That makes public MediaPipe landmark datasets directly mappable onto this pipeline.
final class LandmarkExtractor {
    private let log = Logger(subsystem: "ASLVisionPro", category: "Landmarks")

    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    /// 21 hand joints, matching MediaPipe's ordering.
    static let handJointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    /// 8 upper-body joints that define the signing space.
    /// Index 0 and 1 MUST be the shoulders — `FeatureEncoder` anchors on [0] and scales by
    /// the [0]–[1] distance (shoulder width) to stay invariant to signer distance.
    static let bodyJointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .leftShoulder, .rightShoulder,
        .neck, .nose,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
    ]

    /// Extract landmarks from one frame. Returns `nil` if no hands are found.
    func extract(from pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation,
                 timestamp: TimeInterval) -> SignFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([handRequest, bodyRequest, faceRequest])
        } catch {
            log.error("Vision request failed: \(error.localizedDescription)")
            return nil
        }

        let (left, right) = handLandmarks()
        let frame = SignFrame(
            timestamp: timestamp,
            leftHand: left,
            rightHand: right,
            body: bodyLandmarks(),
            face: faceLandmarks()
        )
        return frame.hasAnyHand ? frame : nil
    }

    // MARK: - Hands

    private func handLandmarks() -> (left: [Landmark], right: [Landmark]) {
        guard let observations = handRequest.results, !observations.isEmpty else { return ([], []) }
        var left: [Landmark] = []
        var right: [Landmark] = []
        for obs in observations {
            guard let points = try? obs.recognizedPoints(.all) else { continue }
            let ordered = Self.handJointOrder.map { landmark(points[$0]) }
            // Vision reports chirality from the camera's view.
            if obs.chirality == .left { left = ordered } else { right = ordered }
        }
        return (left, right)
    }

    // MARK: - Body

    private func bodyLandmarks() -> [Landmark] {
        guard let obs = bodyRequest.results?.first,
              let points = try? obs.recognizedPoints(.all) else { return [] }
        return Self.bodyJointOrder.map { landmark(points[$0]) }
    }

    // MARK: - Face (non-manual markers)

    /// Vision returns a fixed-size point set per revision, so evenly sampling it yields a
    /// stable subset — the same facial positions every frame, which is what matters here.
    private func faceLandmarks() -> [Landmark] {
        guard let obs = faceRequest.results?.first,
              let all = obs.landmarks?.allPoints else { return [] }
        let points = all.normalizedPoints
        guard !points.isEmpty else { return [] }

        let wanted = FeatureEncoder.facePoints
        return (0..<wanted).map { i in
            let idx = points.count > 1 ? (i * (points.count - 1)) / max(1, wanted - 1) : 0
            let p = points[min(idx, points.count - 1)]
            // Same top-left convention as the pose and hand points above.
            return Landmark(position: CGPoint(x: CGFloat(p.x), y: 1 - CGFloat(p.y)),
                            z: 0, confidence: obs.confidence)
        }
    }

    // MARK: - Helpers

    /// A missing or low-confidence joint becomes a zero placeholder so its slot in the
    /// feature vector is preserved. Dropping it would shift every later joint.
    ///
    /// **Y is flipped to a top-left origin.** Vision reports normalized points from the image's
    /// *lower*-left corner, while MediaPipe — and therefore every public landmark corpus we
    /// train on — uses the upper-left. Without this every vertical motion reaches the model
    /// inverted: a hand rising from the forehead looks like a hand falling.
    private func landmark(_ point: VNRecognizedPoint?) -> Landmark {
        guard let point, point.confidence > 0.3 else {
            return Landmark(position: .zero, z: 0, confidence: 0)
        }
        let topLeft = CGPoint(x: point.location.x, y: 1 - point.location.y)
        return Landmark(position: topLeft, z: 0, confidence: point.confidence)
    }
}
