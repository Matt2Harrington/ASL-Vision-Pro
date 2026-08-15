import SwiftUI

/// iOS entry screen. Everything except third-person interpretation is shared with visionOS,
/// and iOS has no entitlement wall — so this is the platform where the most modes actually
/// work today.
///
/// Tutor mode runs through `CameraSignFrameSource`, which adapts the phone camera into the
/// same `SignFrameSource` the headset satisfies with 3D hand tracking. Camera landmarks are
/// 2D, so depth is zero — recognition is weaker than on Vision Pro, but the flow is identical.
struct ModeSelectionView_iOS: View {
    @State private var mode: Mode?

    enum Mode: Hashable { case tutor, interpret, dictionary, collect, listen }

    private var starterLesson: [String] {
        let lesson = SignCatalog.shared.entries.prefix(10).map(\.gloss)
        return lesson.isEmpty ? ["HELLO", "THANK-YOU", "PLEASE"] : Array(lesson)
    }

    var body: some View {
        switch mode {
        case .tutor:
            TutorView_iOS(lesson: starterLesson, onBack: { mode = nil })
        case .interpret:
            ContentView_iOS()
        case .dictionary:
            DictionaryView()
        case .listen:
            if #available(iOS 26.0, *) {
                ListenView()
            } else {
                unavailable("Listen mode needs iOS 26 or newer.")
            }
        case .collect:
            DataCollectorView(prompts: SignCatalog.shared.entries.map(\.gloss),
                              source: CameraSignFrameSource(source: iPhoneCameraSource()),
                              signerID: "signer-1")
        case nil:
            chooser
        }
    }

    private var chooser: some View {
        NavigationStack {
            List {
                Section {
                    row("Tutor", "Practice signing with camera feedback", "hand.raised.fill") { mode = .tutor }
                    row("Dictionary", "Browse signs and their parameters", "book.fill") { mode = .dictionary }
                    if isListenAvailable {
                        row("Listen", "Live speech captions with ASL gloss", "waveform") { mode = .listen }
                    }
                } header: {
                    Text("Available now")
                }

                Section {
                    row("Interpret", "Caption someone else signing", "text.bubble.fill") { mode = .interpret }
                    row("Collect Data", "Record labeled training clips", "record.circle.fill") { mode = .collect }
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Interpret and Collect need a trained model to produce results. Camera landmarks are 2D, so recognition is weaker than on Vision Pro.")
                }
            }
            .navigationTitle("ASL Vision Pro")
        }
    }

    private var isListenAvailable: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text(message).foregroundStyle(.secondary)
            Button("Back") { mode = nil }
        }
        .padding(40)
    }
}

/// iOS tutor: same `TutorSession` as visionOS, fed by the phone camera instead of hand
/// tracking, with a live viewfinder so the user can frame themselves.
struct TutorView_iOS: View {
    @State private var camera: iPhoneCameraSource
    @State private var session: TutorSession
    let onBack: () -> Void

    init(lesson: [String], onBack: @escaping () -> Void) {
        let cam = iPhoneCameraSource()
        _camera = State(initialValue: cam)
        _session = State(initialValue: TutorSession(
            lesson: lesson,
            source: CameraSignFrameSource(source: cam),
            verifier: RecognizerFactory.makeVerifier()
        ))
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let target = session.currentTarget {
                    VStack(spacing: 6) {
                        Text("Sign this").font(.caption).foregroundStyle(.white.opacity(0.8))
                        Text(target)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Text("Lesson complete — \(session.correctCount)/\(session.attemptCount)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                }

                if let attempt = session.lastAttempt {
                    Text(attempt.feedback.message)
                        .font(.headline)
                        .foregroundStyle(attempt.isCorrect ? .green : .orange)
                }

                HStack(spacing: 20) {
                    Button("Back", action: onBack)
                    Button("Skip") { session.skip() }
                        .disabled(session.currentTarget == nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 30)
        }
        .statusBarHidden()
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }
}
