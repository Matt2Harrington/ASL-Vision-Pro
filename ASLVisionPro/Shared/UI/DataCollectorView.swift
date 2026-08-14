import SwiftUI

/// Direction 4 UI — prompt, record, advance. Deliberately spartan: this is an internal tool
/// for building the dataset, not a shipped feature.
struct DataCollectorView: View {
    @State private var collector: DataCollector
    @State private var showExportPath = false

    init(prompts: [String], source: SignFrameSource, signerID: String) {
        _collector = State(initialValue: DataCollector(prompts: prompts,
                                                        source: source,
                                                        signerID: signerID))
    }

    var body: some View {
        VStack(spacing: 26) {
            header

            if let prompt = collector.currentPrompt {
                promptCard(prompt)
                recordControls
            } else {
                doneCard
            }
        }
        .padding(40)
        .onAppear { collector.start() }
        .onDisappear { collector.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Data Collection").font(.title.weight(.semibold))
            ProgressView(value: collector.progress).frame(maxWidth: 340)
            Text("\(collector.clipsRecorded) clips recorded")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func promptCard(_ prompt: String) -> some View {
        VStack(spacing: 10) {
            Text("Sign this").font(.subheadline).foregroundStyle(.secondary)
            Text(prompt)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let n = collector.counts[prompt], n > 0 {
                Text("\(n) recorded").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var recordControls: some View {
        VStack(spacing: 14) {
            Button {
                collector.recordClip()
            } label: {
                Label(collector.isRecording ? "Recording…" : "Record clip",
                      systemImage: collector.isRecording ? "record.circle.fill" : "record.circle")
                    .font(.title3)
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(collector.isRecording ? .red : .accentColor)
            .disabled(collector.isRecording)

            Button("Skip") { collector.skip() }
                .disabled(collector.isRecording)

            Text("Recording captures 2 seconds. Start signing as soon as you tap.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var doneCard: some View {
        VStack(spacing: 14) {
            Text("Session complete").font(.title2.weight(.semibold))
            Text("\(collector.clipsRecorded) clips saved")
                .foregroundStyle(.secondary)
            Button("Show export path") { showExportPath.toggle() }
            if showExportPath {
                Text(DataCollector.recordingsURL().path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
