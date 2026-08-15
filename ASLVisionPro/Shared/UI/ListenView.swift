import SwiftUI

/// "Listen" — the hearing→wearer direction. Microphone audio is transcribed on-device and
/// shown live; ASL gloss with sign parameters is an *optional* second layer.
///
/// Captions lead deliberately. For someone who reads English fluently, a clean caption is
/// often better than a word-order gloss, so the ASL layer is opt-in rather than assumed to be
/// the superior output.
@available(visionOS 26.0, iOS 26.0, macOS 26.0, *)
struct ListenView: View {
    @State private var listener = SpeechListener()
    @State private var showASL = false
    private let translator = GlossTranslator()

    private var tokens: [GlossTranslator.Token] {
        translator.translate(listener.displayText)
    }

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            header
            captionCard
            if showASL { aslCard }
            Spacer(minLength: 0)
            controls
        }
        .padding(32)
        .frame(minWidth: 700)
        .task { await listener.start() }
        .onDisappear { listener.stop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: listener.isListening ? "waveform" : "waveform.slash",
                      tint: listener.isListening ? Theme.Accent.listen : .secondary,
                      size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Listen").font(.title2.weight(.semibold))
                Text(listener.isListening ? "Listening…" : "Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if listener.isListening {
                // Quiet live indicator — no text needed once the state is obvious.
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse)
            }
        }
    }

    // MARK: - Captions

    private var captionCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                if let error = listener.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if listener.displayText.isEmpty {
                    Text("Waiting for speech…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    // Finalized text is settled; volatile text is still being revised, so
                    // it's dimmed to signal it may change.
                    (Text(listener.finalizedText).foregroundStyle(.primary)
                     + Text(listener.volatileText.isEmpty ? "" : " " + listener.volatileText)
                        .foregroundStyle(.secondary))
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .animation(.smooth, value: listener.displayText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
    }

    // MARK: - ASL layer

    private var aslCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "ASL gloss",
                          trailing: tokens.isEmpty ? nil
                                    : "\(Int(translator.coverage(of: tokens) * 100))% signed")

            CardSurface {
                VStack(alignment: .leading, spacing: 14) {
                    if tokens.isEmpty {
                        Text("—").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(tokens) { tokenCard($0) }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Label("Word-order gloss, not full ASL grammar. Unknown words are fingerspelled.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func tokenCard(_ token: GlossTranslator.Token) -> some View {
        switch token {
        case .sign(let entry):
            VStack(alignment: .leading, spacing: 6) {
                IconBadge(symbol: "hand.raised.fill", tint: Theme.Accent.listen, size: 32)
                Text(entry.gloss).font(.headline)
                Text(entry.handshape)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(entry.location)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .padding(14)
            .background(Theme.Accent.listen.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: Theme.innerRadius))

        case .fingerspell(let word):
            VStack(alignment: .leading, spacing: 6) {
                IconBadge(symbol: "textformat.abc", tint: .secondary, size: 32)
                Text(word.uppercased()).font(.headline).lineLimit(1)
                Text("fingerspell")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.innerRadius))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                if listener.isListening { listener.stop() } else { Task { await listener.start() } }
            } label: {
                Label(listener.isListening ? "Stop" : "Start",
                      systemImage: listener.isListening ? "stop.fill" : "mic.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)

            Button {
                listener.clear()
            } label: {
                Label("Clear", systemImage: "trash").frame(minWidth: 100)
            }
            .disabled(listener.displayText.isEmpty)

            Toggle(isOn: $showASL) {
                Label("ASL", systemImage: "hand.raised")
            }
            .toggleStyle(.button)
        }
        .controlSize(.large)
    }
}
