import SwiftUI

/// "Listen" mode — the hearing→wearer direction. Microphone audio is transcribed on-device
/// and shown live; ASL gloss with sign parameters is an *optional* second layer.
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
        VStack(spacing: 22) {
            header
            captionPanel
            if showASL { aslPanel }
            controls
        }
        .padding(36)
        .frame(minWidth: 640)
        .task { await listener.start() }
        .onDisappear { listener.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: listener.isListening ? "waveform" : "waveform.slash")
                .foregroundStyle(listener.isListening ? .green : .secondary)
                .symbolEffect(.variableColor, isActive: listener.isListening)
            Text("Listening").font(.title2.weight(.semibold))
        }
    }

    private var captionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = listener.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if listener.displayText.isEmpty {
                Text("Waiting for speech…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                // Finalized text is settled; volatile text is still being revised, so it's
                // dimmed to show it may change.
                (Text(listener.finalizedText).foregroundStyle(.primary)
                 + Text(listener.volatileText.isEmpty ? "" : " " + listener.volatileText)
                    .foregroundStyle(.secondary))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var aslPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ASL gloss").font(.headline)
                Spacer()
                if !tokens.isEmpty {
                    Text("\(Int(translator.coverage(of: tokens) * 100))% signed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if tokens.isEmpty {
                Text("—").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tokens) { token in
                            tokenCard(token)
                        }
                    }
                }
            }

            Text("Word-order gloss, not full ASL grammar. Unknown words are fingerspelled.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func tokenCard(_ token: GlossTranslator.Token) -> some View {
        switch token {
        case .sign(let entry):
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.gloss).font(.headline)
                Text(entry.handshape).font(.caption2).foregroundStyle(.secondary)
                Text(entry.location).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 150, alignment: .leading)
            .padding(12)
            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

        case .fingerspell(let word):
            VStack(alignment: .leading, spacing: 4) {
                Text(word.uppercased()).font(.headline)
                Label("fingerspell", systemImage: "textformat.abc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button(listener.isListening ? "Stop" : "Start") {
                if listener.isListening { listener.stop() } else { Task { await listener.start() } }
            }
            .buttonStyle(.borderedProminent)

            Button("Clear") { listener.clear() }
            Toggle("Show ASL", isOn: $showASL).toggleStyle(.button)
        }
    }
}
