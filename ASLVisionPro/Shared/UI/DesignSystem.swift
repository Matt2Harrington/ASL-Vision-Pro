import SwiftUI

/// Shared visual language for every screen on both platforms.
///
/// These views are compiled into the visionOS and iOS targets alike, so styling lives here
/// rather than in each screen — otherwise the two drift apart as screens are edited
/// independently. The tokens are tuned for visionOS (generous targets, glass materials,
/// gaze affordances) and read correctly on iOS, where the same materials adapt.
enum Theme {
    /// Card corner radius. Large enough to read as a soft slab on glass.
    static let cardRadius: CGFloat = 28
    /// Nested surfaces inside a card.
    static let innerRadius: CGFloat = 18
    static let cardPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 26
    static let itemSpacing: CGFloat = 20

    /// One stable colour per concept, so a mode is findable by hue rather than by label.
    enum Accent {
        static let practice = Color.blue
        static let dictionary = Color.purple
        static let listen = Color.teal
        static let interpret = Color.orange
        static let collect = Color.pink
    }
}

// MARK: - Building blocks

/// Circular tinted badge behind an SF Symbol. The app's most repeated motif — it marks
/// modes, sign parameters, and section leads with one consistent shape.
struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(tint)
        }
    }
}

/// Quiet section label. Used above every group so screens share one rhythm.
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 4)
    }
}

/// Standard card surface: material background, consistent radius and padding.
struct CardSurface<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Tappable card. Bundles the two things plain buttons in lists and grids always need:
/// an explicit hit shape (otherwise taps on empty space are swallowed) and a hover effect
/// (the primary gaze affordance on visionOS).
struct CardButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.cardPadding)
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .hoverEffect()
    }
}

/// Screen title block. Keeps headers identical across modes.
struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Floating close control. Modes are presented full-screen (the camera ones edge to edge),
/// so they need a dismiss affordance that stays legible over a live camera feed rather than
/// relying on a navigation bar that isn't there.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Close")
    }
}

/// Shown whenever no trained model is bundled, so simulated output is never mistaken for
/// recognition. Deliberately prominent rather than a footnote.
struct SimulatedBanner: View {
    var message = "No trained model — feedback is simulated and unrelated to your signing."

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.orange)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.innerRadius))
    }
}

/// Always-visible honesty label. Recognition can be wrong, and every screen that shows
/// recognized output carries this rather than relying on the user to remember.
struct ExperimentalNote: View {
    var text = "Experimental — recognition may be wrong. Don't rely on it for critical communication."

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
