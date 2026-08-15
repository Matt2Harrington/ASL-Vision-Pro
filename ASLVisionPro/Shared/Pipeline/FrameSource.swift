import CoreVideo
import ImageIO

/// A platform-agnostic source of camera frames for the pipeline.
///
/// This is the single seam between the shared recognition pipeline and the per-platform
/// camera: visionOS supplies frames via the enterprise main-camera API, iOS via
/// AVFoundation. Everything downstream (`LandmarkExtractor` → captions) is identical.
protocol FrameSource: AnyObject {
    /// Begins capture and yields frames until cancelled or `stop()` is called.
    func frames() -> AsyncStream<SourceFrame>
    /// Stops capture and releases the camera.
    func stop()
}

/// One captured frame plus the orientation Vision needs to interpret it. visionOS frames
/// arrive upright (`.up`); a portrait iPhone back camera needs `.right`.
struct SourceFrame {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
}

/// A source that yields `SignFrame`s (landmarks) **directly**, with no Vision pass.
///
/// Two very different producers satisfy this:
///   • `HandTrackingSource` (visionOS) — ARKit already reports 3D joints, so landmark
///     extraction is skipped entirely.
///   • `CameraSignFrameSource` — adapts any camera `FrameSource` by running the extractor.
///
/// Tutor/practice features depend on this protocol rather than a concrete type, so they stay
/// platform-neutral and testable.
/// `@MainActor`: every implementation is main-actor bound (ARKit session, AVFoundation
/// session) and feeds @MainActor UI state. Leaving the protocol nonisolated made the
/// conformance cross actor boundaries, which is a hard error in Swift 6.
@MainActor
protocol SignFrameSource: AnyObject {
    func signFrames() -> AsyncStream<SignFrame>
    func stop()
}

/// Adapts a pixel-buffer `FrameSource` into a `SignFrameSource` by running the landmark
/// extractor. Lets camera-based platforms (iPhone today) drive tutor mode with the same
/// session logic the headset uses.
@MainActor
final class CameraSignFrameSource: SignFrameSource {
    private let source: FrameSource
    private let extractor = LandmarkExtractor()
    private let startTime = Date()

    init(source: FrameSource) {
        self.source = source
    }

    func signFrames() -> AsyncStream<SignFrame> {
        AsyncStream { continuation in
            let task = Task {
                for await captured in source.frames() {
                    let ts = Date().timeIntervalSince(startTime)
                    if let frame = extractor.extract(from: captured.pixelBuffer,
                                                     orientation: captured.orientation,
                                                     timestamp: ts) {
                        continuation.yield(frame)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() { source.stop() }
}
