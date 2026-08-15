import SwiftUI

/// Entry screen. The two modes have very different requirements, and the UI says so plainly
/// rather than letting the user discover it via a failed camera authorization.
struct ModeSelectionView: View {
    @State private var mode: Mode?

    enum Mode: Hashable { case tutor, interpret, dictionary, collect, listen }

    /// Lessons come from the shared catalog, so content and practice never drift apart.
    private var starterLesson: [String] {
        let lesson = SignCatalog.shared.entries.prefix(10).map(\.gloss)
        return lesson.isEmpty ? ["HELLO", "THANK-YOU", "PLEASE"] : Array(lesson)
    }

    var body: some View {
        switch mode {
        case .tutor:
            TutorView(lesson: starterLesson)
        case .interpret:
            ContentView()
        case .listen:
            if #available(visionOS 26.0, *) {
                ListenView()
            } else {
                unavailableView("Listen mode needs visionOS 26 or newer.")
            }
        case .dictionary:
            DictionaryView()
        case .collect:
            DataCollectorView(prompts: SignCatalog.shared.entries.map(\.gloss),
                              source: HandTrackingSource(),
                              signerID: "signer-1")
        case nil:
            chooser
        }
    }

    /// Modes as data so the grid stays symmetric and the list is easy to extend.
    private var modes: [ModeCard] {
        [
            ModeCard(mode: .tutor, title: "Tutor", subtitle: "Practice signing",
                     detail: "Tracks your own hands in 3D and scores each attempt. No special permissions.",
                     symbol: "hand.raised.fill", available: true),
            ModeCard(mode: .dictionary, title: "Dictionary", subtitle: "Look up signs",
                     detail: "Browse signs by category with a full parameter breakdown.",
                     symbol: "book.fill", available: true),
            ModeCard(mode: .listen, title: "Listen", subtitle: "Speech to captions",
                     detail: "Transcribes speech on-device, with optional ASL gloss. Needs visionOS 26.",
                     symbol: "waveform", available: isListenAvailable),
            ModeCard(mode: .collect, title: "Collect Data", subtitle: "Record training clips",
                     detail: "Prompts a sign and records auto-labeled 3D landmarks for training.",
                     symbol: "record.circle.fill", available: true),
            ModeCard(mode: .interpret, title: "Interpret", subtitle: "Caption another person",
                     detail: "Needs Apple's enterprise camera entitlement before it can show captions.",
                     symbol: "text.bubble.fill", available: false),
        ]
    }

    struct ModeCard: Identifiable {
        let mode: Mode
        let title: String
        let subtitle: String
        let detail: String
        let symbol: String
        let available: Bool
        var id: Mode { mode }
    }

    private var chooser: some View {
        VStack(spacing: 36) {
            VStack(spacing: 8) {
                Text("ASL Vision Pro")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose a mode")
                    .foregroundStyle(.secondary)
            }

            // Fixed 3-column grid: five cards land 3-over-2 and stay aligned, rather than
            // the ragged 2-then-3 rows an HStack pair produced.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 24), count: 3),
                      spacing: 24) {
                ForEach(modes) { card in
                    modeCard(card) { mode = card.mode }
                }
            }
        }
        .padding(48)
    }

    private var isListenAvailable: Bool {
        if #available(visionOS 26.0, *) { return true } else { return false }
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text(message).foregroundStyle(.secondary)
            Button("Back") { mode = nil }
        }
        .padding(40)
    }

    private func modeCard(_ card: ModeCard, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: card.symbol).font(.title2)
                    Spacer()
                    if !card.available {
                        Text("Limited")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.3), in: Capsule())
                    }
                }
                Text(card.title).font(.title3.weight(.semibold))
                Text(card.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(card.detail)
                    // .secondary rather than .tertiary: against visionOS glass the tertiary
                    // tier was effectively unreadable over a bright passthrough background.
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(width: 260, height: 190, alignment: .topLeading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .opacity(card.available ? 1 : 0.75)
    }
}
