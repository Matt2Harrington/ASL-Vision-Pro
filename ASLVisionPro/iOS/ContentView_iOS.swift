import SwiftUI

/// iOS camera screen. Deliberately sparse: the camera feed is the subject, and the only thing
/// worth reading at a glance is what the model currently thinks and how sure it is.
///
/// Accumulated captions and the English translation are available but collapsed by default —
/// during live signing they pile up faster than they can be read, and a long sentence on
/// screen implies more certainty than a 5-sign model has earned.
struct ContentView_iOS: View {
    @State private var camera: iPhoneCameraSource
    @State private var pipeline: TranslationPipeline
    @State private var showTracking = true
    @State private var showTranscript = false
    // The camera source isn't observable, so its settings are mirrored here to drive the UI.
    @State private var usingFront = true
    @State private var mirrored = true
    @State private var showCalibration = false
    @State private var threshold: Float = 0.75
    @State private var streak = 2

    init() {
        let cam = iPhoneCameraSource()
        _camera = State(initialValue: cam)
        _pipeline = State(initialValue: TranslationPipeline(source: cam,
                                                            recognizer: RecognizerFactory.makeRecognizer()))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if showTracking, let frame = pipeline.latestFrame {
                LandmarkOverlayView(frame: frame)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                guessPill
                if showTranscript { transcript }
                if showCalibration { calibration }
                controls
            }
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topTrailing) { trackingToggle }
        .statusBarHidden()
        .onAppear { pipeline.start() }
        .onDisappear { pipeline.stop() }
    }

    // MARK: - The one thing worth reading

    /// Current sign and confidence. Green once it clears the gate, dim while it doesn't —
    /// so a near miss is visible rather than looking like nothing happened.
    @ViewBuilder
    private var guessPill: some View {
        if let guess = pipeline.lastGuess {
            HStack(spacing: 12) {
                Text(guess.label)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(guess.accepted ? .green : .white.opacity(0.55))
                Text("\(Int(guess.confidence * 100))%")
                    .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(.black.opacity(0.5), in: Capsule())
            .animation(.smooth(duration: 0.15), value: guess.label)
            .contentTransition(.numericText())
        } else {
            Text("Sign to begin")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.vertical, 22)
        }
    }

    // MARK: - Optional detail

    private var transcript: some View {
        VStack(spacing: 6) {
            if let translation = pipeline.translation {
                Text(translation)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            if !pipeline.caption.isEmpty {
                Text(pipeline.caption)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Live gate tuning. Watching the confidence number while signing shows where the
    /// threshold should sit far more reliably than a validation score does.
    private var calibration: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Confidence").font(.caption).foregroundStyle(.white.opacity(0.7))
                Slider(value: $threshold, in: 0.2...0.95)
                    .onChange(of: threshold) { pipeline.confidenceThreshold = threshold }
                Text("\(Int(threshold * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 42, alignment: .trailing)
            }
            HStack {
                Text("Stability").font(.caption).foregroundStyle(.white.opacity(0.7))
                Stepper("\(streak) window\(streak == 1 ? "" : "s")", value: $streak, in: 1...5)
                    .onChange(of: streak) { pipeline.requiredStreak = streak }
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            smallButton(showTranscript ? "text.bubble.fill" : "text.bubble") {
                showTranscript.toggle()
            }
            smallButton("arrow.counterclockwise") { pipeline.reset() }
            if pipeline.isCalibratable {
                smallButton(showCalibration ? "slider.horizontal.3" : "slider.horizontal.below.square.filled.and.square") {
                    showCalibration.toggle()
                }
            }
            smallButton("arrow.triangle.2.circlepath.camera") {
                camera.flip()
                usingFront = camera.position == .front
                mirrored = camera.isMirrored
            }
            smallButton(mirrored ? "flip.horizontal.fill" : "flip.horizontal") {
                camera.isMirrored.toggle()
                mirrored = camera.isMirrored
            }
            // Naming the active combination matters while comparing them: otherwise a good
            // or bad result can't be attributed to a setting.
            Text("\(usingFront ? "Front" : "Back")\(mirrored ? " · mirrored" : "")")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .contentTransition(.opacity)
        }
        .padding(.top, 14)
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Tracking state lives in the toggle itself — the four detection pills were more text
    /// than the screen could carry, and the dots already show what's tracked.
    private var trackingToggle: some View {
        Button { showTracking.toggle() } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(showTracking ? .cyan : .white.opacity(0.6))
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 12)
    }
}
