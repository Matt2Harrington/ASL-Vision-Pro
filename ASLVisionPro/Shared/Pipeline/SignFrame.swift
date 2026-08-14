import CoreGraphics
import Foundation

/// A single timestamped set of holistic landmarks for the signer being observed.
///
/// This is the abstract "skeleton" that flows through the pipeline after the raw
/// camera frame is discarded. Keeping raw frames out of the pipeline past the
/// extraction stage is a deliberate privacy property (see ARCHITECTURE.md §7).
struct SignFrame {
    /// Seconds since the capture session started.
    let timestamp: TimeInterval

    /// Normalized 2D landmarks in [0, 1] image space. Empty arrays mean "not detected
    /// this frame" (e.g. a hand left the field of view).
    let leftHand: [Landmark]   // up to 21 points (Vision hand pose)
    let rightHand: [Landmark]  // up to 21 points
    let body: [Landmark]       // upper-body pose points relevant to signing space
    let face: [Landmark]       // key non-manual-marker points (brows, mouth, head)

    var hasAnyHand: Bool { !leftHand.isEmpty || !rightHand.isEmpty }
}

/// One normalized landmark with a detection confidence.
struct Landmark {
    let position: CGPoint   // normalized [0,1]
    let confidence: Float   // [0,1]
}

/// A recognized unit emitted by the recognizer: a fingerspelled letter, an isolated
/// sign gloss, or a translated phrase, plus a confidence for UI gating.
struct RecognitionResult: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    let timestamp: TimeInterval
    let kind: Kind

    enum Kind {
        case letter     // fingerspelling (rung 1)
        case sign       // isolated sign gloss (rungs 2–3)
        case phrase     // continuous translation span (rung 4)
    }
}
