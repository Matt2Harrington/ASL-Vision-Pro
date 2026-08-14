import SwiftUI

/// Live caption line. Styled for legibility over passthrough: high-contrast text on a
/// translucent slab. Captions are treated as *revisable* — text updates in place as the
/// pipeline resolves signs, matching how continuous recognition actually settles.
struct CaptionView: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "Waiting for signing…" : text)
            .font(.system(size: 34, weight: .medium, design: .rounded))
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: 900)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .animation(.easeInOut(duration: 0.2), value: text)
            .accessibilityLabel("Live ASL caption")
            .accessibilityValue(text)
    }
}

#Preview {
    VStack(spacing: 24) {
        CaptionView(text: "")
        CaptionView(text: "HELLO NICE MEET YOU")
    }
    .padding()
}
