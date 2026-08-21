import SwiftUI

@main
struct ASLVisionProApp: App {
    // Recognizer comes from the shared factory — identical selection logic to the iOS app.
    @State private var pipeline = TranslationPipeline(source: VisionProCameraSource(),
                                                      recognizer: RecognizerFactory.makeRecognizer())

    var body: some Scene {
        WindowGroup {
            ModeSelectionView()
                .environment(pipeline)
        }
        // Sized so the whole home screen fits without clipping; the simulator's default
        // window was short enough to cut off the second section.
        .defaultSize(width: 1100, height: 820)
        // Default (glass) window style, not .plain: .plain removes the system window
        // background, leaving UI floating directly over passthrough. Verified in the
        // simulator — text was unreadable against a bright wall and legible only where it
        // happened to overlap something dark.
    }
}
