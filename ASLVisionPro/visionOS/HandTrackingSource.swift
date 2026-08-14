import ARKit
import Foundation
import OSLog

/// Wearer-hand `FrameSource` using ARKit `HandTrackingProvider`.
///
/// **No entitlement required** — unlike the main-camera API, hand tracking is standard
/// visionOS and ships on the App Store. It reports ~26 true **3D** joints per hand, which is
/// richer than the 2D landmarks a camera path yields (see ALTERNATIVE_DIRECTIONS.md).
///
/// Constraint: it tracks the **wearer's own hands**, so this powers tutor / practice /
/// data-collection modes, not third-person interpretation.
///
/// Note it produces `SignFrame`s directly rather than pixel buffers — the `LandmarkExtractor`
/// stage is skipped entirely, since ARKit already gives us joints.
@MainActor
final class HandTrackingSource: SignFrameSource {
    private let log = Logger(subsystem: "ASLVisionPro", category: "HandTracking")
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private var task: Task<Void, Never>?
    private let startTime = Date()

    /// Stream of landmark frames built from the wearer's tracked hands.
    func signFrames() -> AsyncStream<SignFrame> {
        AsyncStream { continuation in
            task = Task {
                do {
                    let auth = await session.requestAuthorization(for: [.handTracking])
                    guard auth[.handTracking] == .allowed else {
                        log.error("Hand tracking authorization denied.")
                        continuation.finish()
                        return
                    }
                    try await session.run([provider])
                    log.info("Hand tracking session running.")

                    for await update in provider.anchorUpdates {
                        guard update.event != .removed else { continue }
                        let anchor = update.anchor
                        guard anchor.isTracked else { continue }

                        let joints = Self.landmarks(from: anchor)
                        let ts = Date().timeIntervalSince(startTime)
                        let isLeft = anchor.chirality == .left
                        continuation.yield(SignFrame(
                            timestamp: ts,
                            leftHand: isLeft ? joints : [],
                            rightHand: isLeft ? [] : joints,
                            body: [],    // hand tracking gives no torso; encoder falls back to a fixed anchor
                            face: []     // no face from this provider — a known limit for non-manual markers
                        ))
                    }
                    continuation.finish()
                } catch {
                    log.error("Hand tracking failed: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Convert an ARKit hand skeleton into our `Landmark` list, preserving true 3D.
    /// Positions come from each joint's transform in the anchor's local space.
    private static func landmarks(from anchor: HandAnchor) -> [Landmark] {
        guard let skeleton = anchor.handSkeleton else { return [] }
        return HandSkeleton.JointName.allCases.map { name in
            let joint = skeleton.joint(name)
            let t = joint.anchorFromJointTransform.columns.3
            return Landmark(
                position: CGPoint(x: CGFloat(t.x), y: CGFloat(t.y)),
                z: t.z,
                confidence: joint.isTracked ? 1.0 : 0.0
            )
        }
    }
}
