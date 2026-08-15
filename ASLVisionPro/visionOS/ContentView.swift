import SwiftUI

/// Interpret mode: captions for another person signing in front of the wearer.
///
/// Gated on Apple's enterprise camera entitlement, so the screen says so up front rather
/// than sitting silently empty and looking broken. Everything else here is live — the
/// pipeline runs, and captions appear the moment frames and a model are both available.
struct ContentView: View {
    @Environment(TranslationPipeline.self) private var pipeline
    @State private var showLandmarks = false

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        if showLandmarks, let frame = pipeline.latestFrame {
                            LandmarkOverlayView(frame: frame)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        } else if !pipeline.isRunning {
                            waitingState
                        }
                    }
                    .overlay(alignment: .bottom) {
                        CaptionView(text: pipeline.caption).padding(20)
                    }
            }
            .frame(minWidth: 700, minHeight: 380)

            controls
            ExperimentalNote()
        }
        .padding(32)
        .onAppear { pipeline.start() }
        .onDisappear { pipeline.stop() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "text.bubble.fill", tint: Theme.Accent.interpret, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Interpret").font(.title2.weight(.semibold))
                Text(pipeline.isRunning ? "Watching for signing" : "Camera unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pipeline.isRunning {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    /// Shown instead of a blank panel when no frames are arriving — almost always the
    /// missing entitlement, so it names that rather than leaving the user guessing.
    private var waitingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No camera feed")
                .font(.title3.weight(.medium))
            Text("Interpret needs Apple's enterprise main-camera entitlement before it can see another person.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(30)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                pipeline.isRunning ? pipeline.stop() : pipeline.start()
            } label: {
                Label(pipeline.isRunning ? "Stop" : "Start",
                      systemImage: pipeline.isRunning ? "stop.fill" : "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)

            Toggle(isOn: $showLandmarks) {
                Label("Landmarks", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .toggleStyle(.button)
        }
        .controlSize(.large)
    }
}
