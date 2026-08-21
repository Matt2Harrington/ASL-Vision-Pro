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

    enum Mode: Hashable, Identifiable {
        case tutor, interpret, dictionary, collect, listen, translationCheck
        var id: Self { self }
    }

    private var starterLesson: [String] {
        let lesson = SignCatalog.shared.entries.prefix(10).map(\.gloss)
        return lesson.isEmpty ? ["HELLO", "THANK-YOU", "PLEASE"] : Array(lesson)
    }

    var body: some View {
        switch mode {
        case nil:
            chooser
        default:
            // Every mode is presented full-screen, so each needs its own dismiss control —
            // there's no navigation bar to fall back on, and the camera modes cover the
            // entire display.
            modeContent
                .overlay(alignment: .topLeading) {
                    CloseButton { mode = nil }
                        .padding(.leading, 16)
                        .padding(.top, 12)
                }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .tutor:
            TutorView_iOS(lesson: starterLesson)
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
        case .translationCheck:
            NavigationStack { TranslationCheckView() }
        case nil:
            EmptyView()
        }
    }

    private var chooser: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    ScreenHeader(title: "ASL Vision Pro",
                                 subtitle: "Learn, look up, and follow along — all on device")
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)

                    section("Start here", items: primaryModes)
                    section("More", items: secondaryModes)
                }
                .padding(24)
            }
        }
    }

    private func section(_ title: String, items: [ModeInfo]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Theme.itemSpacing)],
                      spacing: Theme.itemSpacing) {
                ForEach(items) { info in
                    CardButton { mode = info.mode } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            IconBadge(symbol: info.symbol, tint: info.tint)
                            Text(info.title).font(.title3.weight(.semibold))
                            Text(info.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let note = info.note {
                                Label(note, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
            }
        }
    }

    struct ModeInfo: Identifiable {
        let mode: Mode
        let title: String
        let summary: String
        let symbol: String
        let tint: Color
        var note: String? = nil
        var id: Mode { mode }
    }

    /// Works right now — no model, no entitlement.
    private var primaryModes: [ModeInfo] {
        var modes = [
            ModeInfo(mode: .tutor, title: "Practice",
                     summary: "Sign along and get feedback on every attempt.",
                     symbol: "hand.raised.fill", tint: Theme.Accent.practice),
            ModeInfo(mode: .dictionary, title: "Dictionary",
                     summary: "Look up any sign and see how it's formed.",
                     symbol: "book.fill", tint: Theme.Accent.dictionary),
        ]
        if isListenAvailable {
            modes.append(ModeInfo(mode: .listen, title: "Listen",
                                  summary: "Turn nearby speech into live captions.",
                                  symbol: "waveform", tint: Theme.Accent.listen))
        }
        return modes
    }

    /// Gated or internal — demoted, with the reason stated up front.
    private var secondaryModes: [ModeInfo] {
        [
            ModeInfo(mode: .interpret, title: "Interpret",
                     summary: "Caption someone else signing to you.",
                     symbol: "text.bubble.fill", tint: Theme.Accent.interpret,
                     note: "Needs a trained model"),
            ModeInfo(mode: .collect, title: "Record Clips",
                     summary: "Build training data for the recognizer.",
                     symbol: "record.circle.fill", tint: Theme.Accent.collect,
                     note: "For development"),
            ModeInfo(mode: .translationCheck, title: "Translation Check",
                     summary: "See how the on-device model turns glosses into English.",
                     symbol: "brain", tint: Theme.Accent.listen,
                     note: "For development"),
        ]
    }

    private var isListenAvailable: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text(message).foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

/// iOS tutor: same `TutorSession` as visionOS, fed by the phone camera instead of hand
/// tracking, with a live viewfinder so the user can frame themselves.
struct TutorView_iOS: View {
    @State private var camera: iPhoneCameraSource
    @State private var session: TutorSession

    init(lesson: [String]) {
        let cam = iPhoneCameraSource()
        _camera = State(initialValue: cam)
        _session = State(initialValue: TutorSession(
            lesson: lesson,
            source: CameraSignFrameSource(source: cam),
            verifier: RecognizerFactory.makeVerifier()
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if !RecognizerFactory.hasBundledModel {
                    SimulatedBanner()
                        .padding(.horizontal, 20)
                }

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

                Button("Skip") { session.skip() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.currentTarget == nil)
            }
            .padding(.bottom, 30)
        }
        .statusBarHidden()
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }
}
