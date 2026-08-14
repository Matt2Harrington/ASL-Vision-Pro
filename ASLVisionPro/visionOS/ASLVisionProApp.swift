import SwiftUI

@main
struct ASLVisionProApp: App {
    // Recognizer comes from the shared factory — identical selection logic to the iOS app.
    @State private var pipeline = TranslationPipeline(source: VisionProCameraSource(),
                                                      recognizer: RecognizerFactory.makeRecognizer())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pipeline)
        }
        .windowStyle(.plain)
    }
}
