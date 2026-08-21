import SwiftUI

/// Live caption. Shows the English translation as the headline when a language model produced
/// one, with the raw recognized glosses beneath it.
///
/// The gloss line is never hidden. It is what the recognizer actually saw; the English is an
/// interpretation layered on top. Keeping both visible means a wrong translation is
/// inspectable rather than authoritative — which matters when the output speaks for a person.
struct CaptionView: View {
    let text: String
    var translation: String? = nil
    var isTranslating: Bool = false

    private var hasContent: Bool { !text.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            if !hasContent {
                Text("Waiting for signing…")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                if let translation {
                    Text(translation)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                HStack(spacing: 8) {
                    if translation != nil {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(text)
                        .font(translation == nil
                              ? .system(size: 30, weight: .medium, design: .rounded)
                              : .callout.monospaced())
                        .foregroundStyle(translation == nil ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                    if isTranslating {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .lineLimit(3)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: 900)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .animation(.smooth(duration: 0.25), value: translation)
        .animation(.smooth(duration: 0.2), value: text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live ASL caption")
        .accessibilityValue(translation.map { "\($0). Glosses: \(text)" } ?? text)
    }
}

#Preview {
    VStack(spacing: 24) {
        CaptionView(text: "")
        CaptionView(text: "HELLO NICE MEET YOU")
        CaptionView(text: "ME NAME M-A-T-T",
                    translation: "My name is Matt.",
                    isTranslating: false)
    }
    .padding()
}
