import Foundation
import OSLog

/// Turns a sequence of recognized ASL glosses into readable English.
///
/// This is the second half of a two-stage translation pipeline:
///
///     landmarks -> Core ML classifier -> glosses -> interpreter -> English
///
/// The split matters. The classifier *perceives* — it's fast, has calibrated confidence, and
/// reads motion. It cannot produce English, because ASL has its own grammar: topic-comment
/// order, spatial reference, no articles or copulas. Concatenating glosses gives word salad
/// (RECOGNITION_APPROACH.md, Level 3). A language model handles exactly that gap.
///
/// Crucially the interpreter only ever sees **text**, never video or landmarks — so adding it
/// costs nothing in privacy even if a non-local model is ever swapped in behind this protocol.
protocol GlossInterpreting: AnyObject {
    /// Returns fluent English for the gloss sequence, or nil if it can't produce one.
    func interpret(_ glosses: [String]) async -> String?
    /// Human-readable description of what's actually running, so the UI can distinguish a
    /// real translation from a passthrough that merely looks like one.
    var displayName: String { get }
}

/// Fallback used when no language model is available: joins the glosses as-is. This is the
/// original behaviour — honest gloss output rather than a fabricated sentence.
final class PassthroughGlossInterpreter: GlossInterpreting {
    var displayName: String { "No language model — glosses shown as-is" }

    func interpret(_ glosses: [String]) async -> String? {
        glosses.isEmpty ? nil : glosses.joined(separator: " ")
    }
}

/// Chooses the best available interpreter. Mirrors `RecognizerFactory` so both stages of the
/// pipeline are configured the same way, from one place, on both platforms.
enum GlossInterpreterFactory {
    private static let log = Logger(subsystem: "ASLVisionPro", category: "GlossInterpreter")

    static func make() -> GlossInterpreting {
        if #available(iOS 26.0, visionOS 26.0, macOS 26.0, *) {
            if let interpreter = FoundationModelGlossInterpreter() {
                log.info("Using on-device Foundation Model for gloss translation.")
                return interpreter
            }
            log.notice("Foundation Model unavailable — falling back to raw gloss output.")
        }
        return PassthroughGlossInterpreter()
    }
}
