import AVFoundation
import CoreVideo
import OSLog

/// iOS `FrameSource` backed by AVFoundation. Uses the **back** wide-angle camera to film the
/// person opposite the user. Standard camera access — no special entitlement, App Store OK.
///
/// The `session` is exposed so a `CameraPreview` can show a live viewfinder from the same
/// capture session the pipeline consumes.
final class iPhoneCameraSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    /// Front camera by default.
    ///
    /// The public landmark corpora we train on were captured on smartphone selfie cameras, so
    /// the front camera matches the viewpoint and handedness the model learned. It is also the
    /// natural choice for practising your own signing. The back camera remains available for
    /// filming someone else.
    private(set) var position: AVCaptureDevice.Position

    /// Whether frames are mirrored before landmark extraction.
    ///
    /// This is deliberately independent of which camera is active. Mirroring flips a hand's
    /// apparent chirality, so it decides whether the signer's right hand lands in the right
    /// hand's feature slots — which matters a great deal to a hands-only model. The corpora we
    /// train on were captured on selfie cameras, but whether their frames were mirrored before
    /// landmarks were extracted isn't documented, so this is exposed as a control to settle
    /// empirically rather than assumed.
    var isMirrored: Bool

    init(position: AVCaptureDevice.Position = .front, mirrored: Bool? = nil) {
        self.position = position
        self.isMirrored = mirrored ?? (position == .front)
        super.init()
    }

    private let log = Logger(subsystem: "ASLVisionPro", category: "iOSCamera")
    private let queue = DispatchQueue(label: "com.mattharrington.aslvisionpro.camera")
    private var continuation: AsyncStream<SourceFrame>.Continuation?
    private var configured = false

    func frames() -> AsyncStream<SourceFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
            Task { await self.configureAndStart() }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        continuation?.finish()
        continuation = nil
    }

    private func configureAndStart() async {
        guard await requestPermission() else {
            log.error("Camera permission denied.")
            continuation?.finish()
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configureSession() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        } else {
            log.error("Could not add camera input.")
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        configured = true
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        continuation?.yield(SourceFrame(pixelBuffer: pixelBuffer, orientation: orientation))
    }

    /// Portrait orientation for the active camera, with mirroring applied.
    ///
    /// Vision needs `.right` to read a portrait back-camera frame upright and `.left` for the
    /// front camera, which is physically rotated the other way; the `Mirrored` variants add
    /// the horizontal flip.
    private var orientation: CGImagePropertyOrientation {
        switch (position, isMirrored) {
        case (.front, true):  return .leftMirrored
        case (.front, false): return .left
        case (_, true):       return .rightMirrored
        case (_, false):      return .right
        }
    }

    /// Swap cameras. Mirroring follows the camera's usual convention, but can be overridden
    /// afterwards with `isMirrored`.
    func flip() {
        position = (position == .front) ? .back : .front
        isMirrored = (position == .front)
        queue.async { [weak self] in
            guard let self else { return }
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                    position: self.position),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
            if wasRunning { self.session.startRunning() }
        }
    }
}
