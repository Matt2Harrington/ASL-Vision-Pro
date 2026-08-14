import ARKit
import CoreVideo
import OSLog

/// visionOS `FrameSource` backed by the **Enterprise** main-camera API
/// (`CameraFrameProvider`). Requires the managed `main-camera-access` entitlement + license
/// (see ARCHITECTURE.md §1); without them, authorization is denied and the stream ends
/// immediately. Exercise on real Vision Pro hardware — the simulator has no camera.
final class VisionProCameraSource: FrameSource {
    private let log = Logger(subsystem: "ASLVisionPro", category: "VisionCamera")
    private let session = ARKitSession()
    private let frameProvider = CameraFrameProvider()
    private var task: Task<Void, Never>?

    func frames() -> AsyncStream<SourceFrame> {
        AsyncStream { continuation in
            task = Task {
                do {
                    try await start()
                    let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
                    guard let format = formats.first else {
                        log.error("No supported main-camera video format for this entitlement scope.")
                        continuation.finish()
                        return
                    }
                    guard let updates = frameProvider.cameraFrameUpdates(for: format) else {
                        log.error("Could not open camera frame updates for the selected format.")
                        continuation.finish()
                        return
                    }
                    for await frame in updates {
                        let sample = frame.primarySample
                        continuation.yield(SourceFrame(pixelBuffer: sample.pixelBuffer, orientation: .up))
                    }
                    continuation.finish()
                } catch {
                    log.error("Camera feed failed: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func start() async throws {
        // Fails here if the enterprise entitlement / license is missing or denied.
        let result = await session.requestAuthorization(for: [.cameraAccess])
        guard result[.cameraAccess] == .allowed else { throw CameraError.authorizationDenied }
        try await session.run([frameProvider])
        log.info("Main-camera session running.")
    }

    enum CameraError: Error { case authorizationDenied }
}
