import SwiftUI

/// iOS camera screen. Full-screen viewfinder with live captions, plus a tracking overlay.
///
/// The overlay exists because it's the one part of this screen that produces real output
/// today: Vision genuinely finds hands, while recognition is still a stub. It answers the
/// question that actually matters before collecting training data — does tracking hold up in
/// this room, at this distance, with these hands?
struct ContentView_iOS: View {
    @State private var camera: iPhoneCameraSource
    @State private var pipeline: TranslationPipeline
    @State private var showTracking = true

    init() {
        let cam = iPhoneCameraSource()
        _camera = State(initialValue: cam)
        // Recognizer comes from the shared factory — identical selection logic to visionOS.
        _pipeline = State(initialValue: TranslationPipeline(source: cam,
                                                            recognizer: RecognizerFactory.makeRecognizer()))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if showTracking, let frame = pipeline.latestFrame {
                LandmarkOverlayView(frame: frame)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                if showTracking { trackingReadout }
                if showTracking, let guess = pipeline.lastGuess { guessReadout(guess) }

                CaptionView(text: pipeline.caption,
                            translation: pipeline.translation,
                            isTranslating: pipeline.isTranslating)

                Text("Experimental — recognition may be wrong. Do not rely on it for critical communication.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .shadow(radius: 3)
            }
            .padding(.bottom, 32)
        }
        .overlay(alignment: .topTrailing) {
            Toggle(isOn: $showTracking) {
                Label("Tracking", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .padding()
        }
        .statusBarHidden()
        .onAppear { pipeline.start() }
        .onDisappear { pipeline.stop() }
    }

    /// Live per-region detection state. Vision reports each region independently, so seeing
    /// which ones are landing tells you whether to move closer, improve lighting, or reframe.
    private var trackingReadout: some View {
        let frame = pipeline.latestFrame
        return HStack(spacing: 10) {
            pill("L hand", detected: !(frame?.leftHand.isEmpty ?? true), tint: .cyan)
            pill("R hand", detected: !(frame?.rightHand.isEmpty ?? true), tint: .cyan)
            pill("Body", detected: !(frame?.body.isEmpty ?? true), tint: .yellow)
            pill("Face", detected: !(frame?.face.isEmpty ?? true), tint: .pink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45), in: Capsule())
    }

    /// The model's best guess and how sure it is. A rejected guess is shown greyed rather
    /// than hidden — seeing "NO at 41%" tells you the model is close, which an empty caption
    /// does not.
    private func guessReadout(_ guess: CoreMLSignRecognizer.Peek) -> some View {
        HStack(spacing: 8) {
            Text(guess.label)
                .font(.headline)
                .foregroundStyle(guess.accepted ? .green : .white.opacity(0.7))
            Text("\(Int(guess.confidence * 100))%")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            if !guess.accepted {
                Text("below threshold")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private func pill(_ label: String, detected: Bool, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(detected ? tint : .white.opacity(0.25))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(detected ? .white : .white.opacity(0.5))
        }
    }
}
