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
