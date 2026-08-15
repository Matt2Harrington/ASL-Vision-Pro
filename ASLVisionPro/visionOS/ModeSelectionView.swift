import SwiftUI

/// visionOS home. Designed to be understood at a glance and driven with one look-and-pinch:
///
///  • Modes that work right now come first and are visually dominant; anything gated is
///    demoted and labelled, so nobody walks into a dead end wondering why nothing happens.
///  • Cards are large and generously spaced — comfortable gaze targets matter far more on
///    visionOS than information density.
///  • One accent colour per mode gives each a stable identity you can find by shape and hue
///    instead of re-reading every label.
struct ModeSelectionView: View {
    @State private var mode: Mode?

    enum Mode: Hashable, Identifiable {
        case tutor, dictionary, listen, collect, interpret
        var id: Self { self }
    }

    /// Lessons come from the shared catalog, so content and practice never drift apart.
    private var starterLesson: [String] {
        let lesson = SignCatalog.shared.entries.prefix(10).map(\.gloss)
        return lesson.isEmpty ? ["HELLO", "THANK-YOU", "PLEASE"] : Array(lesson)
    }

    var body: some View {
        switch mode {
        case .tutor:      TutorView(lesson: starterLesson)
        case .dictionary: DictionaryView()
        case .listen:
            if #available(visionOS 26.0, *) { ListenView() }
            else { unavailable("Listen needs visionOS 26 or newer.") }
        case .collect:
            DataCollectorView(prompts: SignCatalog.shared.entries.map(\.gloss),
                              source: HandTrackingSource(),
                              signerID: "signer-1")
        case .interpret:  ContentView()
        case nil:         home
        }
    }

    // MARK: - Home

    private var home: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Start here", items: primaryModes, prominent: true)
                    section("More", items: secondaryModes, prominent: false)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
        }
        .padding(40)
        .frame(minWidth: 960)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("ASL Vision Pro")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Learn, look up, and follow along — all on device")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 28)
    }

    private func section(_ title: String, items: [ModeInfo], prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 20),
                               count: prominent ? 3 : 2),
                spacing: 20
            ) {
                ForEach(items) { card(for: $0, prominent: prominent) }
            }
        }
    }

    // MARK: - Card

    private func card(for info: ModeInfo, prominent: Bool) -> some View {
        Button { mode = info.mode } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(info.tint.opacity(0.22))
                        .frame(width: prominent ? 54 : 46, height: prominent ? 54 : 46)
                    Image(systemName: info.symbol)
                        .font(.system(size: prominent ? 24 : 20, weight: .medium))
                        .foregroundStyle(info.tint)
                }
                .padding(.bottom, prominent ? 14 : 12)

                Text(info.title)
                    .font(prominent ? .title2.weight(.semibold) : .title3.weight(.semibold))
                Text(info.summary)
                    .font(prominent ? .body : .callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                if let note = info.note {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: prominent ? 198 : 150)
            .padding(prominent ? 22 : 20)
            // Explicit hit shape: plain buttons otherwise only respond on opaque content.
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .hoverEffect()   // gaze feedback — the primary affordance on visionOS
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44))
            Text(message).font(.title3).foregroundStyle(.secondary)
            Button("Back") { mode = nil }.buttonStyle(.borderedProminent)
        }
        .padding(50)
    }

    // MARK: - Content

    struct ModeInfo: Identifiable {
        let mode: Mode
        let title: String
        let summary: String
        let symbol: String
        let tint: Color
        var note: String? = nil
        var id: Mode { mode }
    }

    /// Works right now — no model, no entitlement.
    private var primaryModes: [ModeInfo] {
        var modes = [
            ModeInfo(mode: .tutor, title: "Practice",
                     summary: "Sign along and get feedback on every attempt.",
                     symbol: "hand.raised.fill", tint: .blue),
            ModeInfo(mode: .dictionary, title: "Dictionary",
                     summary: "Look up any sign and see how it's formed.",
                     symbol: "book.fill", tint: .purple),
        ]
        if #available(visionOS 26.0, *) {
            modes.append(ModeInfo(mode: .listen, title: "Listen",
                                  summary: "Turn nearby speech into live captions.",
                                  symbol: "waveform", tint: .teal))
        }
        return modes
    }

    /// Gated or internal — demoted, with the reason stated up front.
    private var secondaryModes: [ModeInfo] {
        [
            ModeInfo(mode: .interpret, title: "Interpret",
                     summary: "Caption someone else signing to you.",
                     symbol: "text.bubble.fill", tint: .orange,
                     note: "Needs Apple's camera entitlement"),
            ModeInfo(mode: .collect, title: "Record Clips",
                     summary: "Build training data for the recognizer.",
                     symbol: "record.circle.fill", tint: .pink,
                     note: "For development"),
        ]
    }
}
