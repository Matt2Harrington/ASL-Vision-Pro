import CoreVideo
import ImageIO
import Vision
import OSLog

/// Phase 1 — turn a camera frame into holistic landmarks for the signer.
///
/// Runs Apple Vision requests on-device: hand pose (both hands), upper-body pose, and
/// face landmarks (for non-manual markers). All three feed the recognizer; hands carry
/// most lexical content, face/body carry grammar and signing-space cues.
///
/// NOTE: For higher-fidelity holistic tracking you may swap in an on-device MediaPipe
/// Holistic graph here; the output `SignFrame` contract stays identical so nothing
/// downstream changes.
final class LandmarkExtractor {
    private let log = Logger(subsystem: "ASLVisionPro", category: "Landmarks")

    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    /// Extract landmarks from one frame. Returns `nil` if no person/hands are found.
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
            let points = landmarks(from: try? obs.recognizedPoints(.all))
            // Vision reports chirality from the camera's view; map to signer's L/R downstream if needed.
            if obs.chirality == .left { left = points } else { right = points }
        }
        return (left, right)
    }

    // MARK: - Body

    private func bodyLandmarks() -> [Landmark] {
        guard let obs = bodyRequest.results?.first else { return [] }
        return landmarks(from: try? obs.recognizedPoints(.all))
    }

    // MARK: - Face (non-manual markers)

    private func faceLandmarks() -> [Landmark] {
        guard let obs = faceRequest.results?.first,
              let region = obs.landmarks?.allPoints else { return [] }
        return region.normalizedPoints.map { Landmark(position: CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)),
                                                       confidence: obs.confidence) }
    }

    // MARK: - Helpers

    /// Generic over the joint-name key type, so it accepts both hand-pose and body-pose
    /// point dictionaries (which use distinct `JointName` types).
    private func landmarks<Key>(from recognized: [Key: VNRecognizedPoint]?) -> [Landmark] {
        guard let recognized else { return [] }
        return recognized.values
            .filter { $0.confidence > 0.3 }
            .map { Landmark(position: $0.location, confidence: $0.confidence) }
    }
}
