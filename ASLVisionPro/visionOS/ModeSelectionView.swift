import SwiftUI

/// Entry screen. The two modes have very different requirements, and the UI says so plainly
/// rather than letting the user discover it via a failed camera authorization.
struct ModeSelectionView: View {
    @State private var mode: Mode?

    enum Mode: Hashable { case tutor, interpret }

    /// Starter lesson — pulled from the Level-2 vocabulary (training/VOCABULARY.md).
    private let starterLesson = ["HELLO", "THANK-YOU", "PLEASE", "YES", "NO",
                                 "NAME", "HELP", "GOOD", "SORRY", "FRIEND"]

    var body: some View {
        switch mode {
        case .tutor:
            TutorView(lesson: starterLesson)
        case .interpret:
            ContentView()
        case nil:
            chooser
        }
    }

    private var chooser: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("ASL Vision Pro")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose a mode")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                modeCard(
                    title: "Tutor",
                    subtitle: "Practice signing",
                    detail: "Tracks your own hands in 3D and scores each attempt. Works today — no special permissions.",
                    systemImage: "hand.raised.fill",
                    available: true
                ) { mode = .tutor }

                modeCard(
                    title: "Interpret",
                    subtitle: "Caption another person",
                    detail: "Needs Apple's enterprise camera entitlement. Runs without captions until that's approved.",
                    systemImage: "text.bubble.fill",
                    available: false
                ) { mode = .interpret }
            }
        }
        .padding(48)
    }

    private func modeCard(title: String, subtitle: String, detail: String,
                          systemImage: String, available: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title)
                    Spacer()
                    if !available {
                        Text("Limited")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.25), in: Capsule())
                    }
                }
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 240, height: 200, alignment: .topLeading)
            .padding(20)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
