import SwiftUI

/// iOS app entry (backup platform — iPhone camera instead of Vision Pro passthrough).
/// Compiled only into the iOS target; the visionOS target has its own `@main`.
@main
struct ASLVisionProApp_iOS: App {
    var body: some Scene {
        WindowGroup {
            ContentView_iOS()
        }
    }
}
