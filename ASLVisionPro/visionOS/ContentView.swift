import SwiftUI

/// The single, simple screen: the signer in view with live captions beneath, plus a
/// start/stop control and an "experimental" disclaimer that is intentionally always visible.
struct ContentView: View {
    @Environment(TranslationPipeline.self) private var pipeline
    @State private var showDebugOverlay = false

    var body: some View {
        VStack(spacing: 20) {
            header

            ZStack {
                // On Vision Pro the passthrough shows the real person; this view frames the
                // caption region and (optionally) the landmark debug overlay on top.
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.15))
                    .overlay {
                        if showDebugOverlay, let frame = pipeline.latestFrame {
                            LandmarkOverlayView(frame: frame)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        CaptionView(text: pipeline.caption)
                            .padding(24)
                    }
            }
            .frame(minWidth: 720, minHeight: 480)

            controls
            disclaimer
        }
        .padding(32)
        .onAppear { pipeline.start() }
        .onDisappear { pipeline.stop() }
    }

    private var header: some View {
        Text("ASL Vision Pro")
            .font(.largeTitle.weight(.semibold))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button(pipeline.isRunning ? "Stop" : "Start") {
                pipeline.isRunning ? pipeline.stop() : pipeline.start()
            }
            .buttonStyle(.borderedProminent)

            Toggle("Show landmarks", isOn: $showDebugOverlay)
                .toggleStyle(.button)

            Label(pipeline.isRunning ? "Live" : "Paused",
                  systemImage: pipeline.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle")
                .foregroundStyle(pipeline.isRunning ? .green : .secondary)
        }
    }

    private var disclaimer: some View {
        Text("Experimental — recognition may be wrong. Do not rely on it for critical communication.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
