import Foundation

/// Segments a continuous landmark stream into candidate sign spans.
///
/// Continuous signing has no spaces (co-articulation), so we can't classify per-frame.
/// This buffers frames and emits a fixed-length sliding window whenever there is enough
/// hand motion to plausibly contain a sign. A learned boundary detector can replace this
/// heuristic later — the `WindowReady` contract is what the recognizer depends on.
final class SignSegmenter {
    struct Window {
        let frames: [SignFrame]
    }

    private var buffer: [SignFrame] = []
    private let windowSize: Int          // frames per classified span
    private let stride: Int              // frames between emitted windows
    private var framesSinceEmit = 0

    init(windowSize: Int = 24, stride: Int = 8) {
        self.windowSize = windowSize
        self.stride = stride
    }

    /// Feed one frame; returns a window when one is ready to classify, else `nil`.
    func accept(_ frame: SignFrame) -> Window? {
        buffer.append(frame)
        if buffer.count > windowSize { buffer.removeFirst(buffer.count - windowSize) }
        framesSinceEmit += 1

        guard buffer.count == windowSize, framesSinceEmit >= stride else { return nil }
        guard hasActiveSigning() else { return nil }

        framesSinceEmit = 0
        return Window(frames: buffer)
    }

    /// Cheap activity gate: skip windows where the hands are essentially still, so we don't
    /// spend Neural Engine cycles (and battery) classifying rest poses. Replace with a
    /// learned start/stop detector in Phase 3.
    private func hasActiveSigning() -> Bool {
        let hands = buffer.map { $0.hasAnyHand }
        let activeRatio = Double(hands.filter { $0 }.count) / Double(hands.count)
        return activeRatio > 0.6
    }
}
