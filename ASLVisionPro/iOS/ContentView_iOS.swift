import SwiftUI

/// The iOS screen: full-screen camera viewfinder with live captions overlaid at the bottom.
/// Point the phone at the signer; captions stream beneath. Same pipeline as visionOS —
/// only the frame source (iPhone camera) and this shell differ.
struct ContentView_iOS: View {
    @State private var camera: iPhoneCameraSource
    @State private var pipeline: TranslationPipeline

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

            VStack(spacing: 12) {
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
        .statusBarHidden()
        .onAppear { pipeline.start() }
        .onDisappear { pipeline.stop() }
    }
}
