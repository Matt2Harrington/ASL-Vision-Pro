import SwiftUI

/// Data collection. An internal tool, but it shares the app's visual language so switching
/// into it isn't jarring — and because recording sessions are long, the state of things
/// (what to sign, whether it's recording, how far along) has to be readable at a glance.
struct DataCollectorView: View {
    @State private var collector: DataCollector
    @State private var showExportPath = false

    init(prompts: [String], source: SignFrameSource, signerID: String) {
        _collector = State(initialValue: DataCollector(prompts: prompts,
                                                        source: source,
                                                        signerID: signerID))
    }

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            header

            if let prompt = collector.currentPrompt {
                promptCard(prompt)
                recordControls
            } else {
                completionCard
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(minWidth: 640)
        .onAppear { collector.start() }
        .onDisappear { collector.stop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                IconBadge(symbol: "record.circle.fill", tint: Theme.Accent.collect, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record Clips").font(.title2.weight(.semibold))
                    Text("\(collector.clipsRecorded) recorded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            ProgressView(value: collector.progress).tint(Theme.Accent.collect)
        }
    }

    // MARK: - Prompt

    private func promptCard(_ prompt: String) -> some View {
        CardSurface {
            VStack(spacing: 14) {
                Text("Sign this")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(prompt)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: prompt)

                if let n = collector.counts[prompt], n > 0 {
                    Label("\(n) already recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Controls

    private var recordControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    collector.recordClip()
                } label: {
                    Label(collector.isRecording ? "Recording…" : "Record clip",
                          systemImage: collector.isRecording ? "record.circle.fill" : "record.circle")
                        .frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .tint(collector.isRecording ? .red : Theme.Accent.collect)
                .disabled(collector.isRecording)

                Button {
                    collector.skip()
                } label: {
                    Label("Skip", systemImage: "forward.fill").frame(minWidth: 110)
                }
                .disabled(collector.isRecording)
            }
            .controlSize(.large)

            Text("Captures 2 seconds. Start signing as soon as you tap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Completion

    private var completionCard: some View {
        CardSurface {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                Text("Session complete")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("\(collector.clipsRecorded) clips saved")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button {
                    showExportPath.toggle()
                } label: {
                    Label(showExportPath ? "Hide export path" : "Show export path",
                          systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)

                if showExportPath {
                    Text(collector.outputURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.innerRadius))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
