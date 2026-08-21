import Foundation
import FoundationModels
import OSLog

/// Gloss → English using Apple's **on-device** language model (Foundation Models framework).
///
/// This is what lets the app produce real English without giving up the privacy property the
/// whole architecture is built on: the model runs locally, needs no network, and — unlike a
/// cloud vision model reading camera frames — only ever sees a short list of recognized
/// glosses, never footage of a person.
///
/// Returns nil rather than guessing when the model is unavailable or the output looks wrong,
/// so the caller can fall back to showing the raw glosses. For an assistive tool, honest
/// gloss output beats a confidently fabricated sentence.
@available(iOS 26.0, visionOS 26.0, macOS 26.0, *)
final class FoundationModelGlossInterpreter: GlossInterpreting {
    private let log = Logger(subsystem: "ASLVisionPro", category: "GlossInterpreter")
    private let session: LanguageModelSession

    /// Guardrails matter more than fluency here. The model is told to translate only what it
    /// is given, because an LLM asked to "make this a sentence" will happily invent content
    /// the signer never signed — which in an interpreting context misrepresents a person.
    private static let instructions = """
    You translate American Sign Language gloss sequences into natural English.

    ASL gloss is written in capitals and omits English function words. It uses
    topic-comment order and its own grammar, so a word-for-word reading is not English.
    Hyphenated glosses such as THANK-YOU are a single sign. Letters separated by hyphens,
    like M-A-T-T, are fingerspelling and are usually a name or a word with no sign.

    Rules:
    - Translate ONLY what the glosses contain. Never add facts, names, or details.
    - Add the English function words the glosses omit (articles, "is", "to").
    - Keep it short and literal. Do not embellish or explain.
    - Reply with the sentence alone. No quotes, no notes, no alternatives.
    - If the glosses are too few or incoherent to translate, reply with exactly: UNCLEAR
    """

    /// Set once inference has failed repeatedly, so we stop paying for calls that cannot
    /// succeed. `isAvailable` is necessary but not sufficient: it reports true in the
    /// simulator, where the model assets are absent and every request fails. Without this the
    /// app would claim to be translating while silently declining forever.
    private var consecutiveFailures = 0
    private var isUsable = true
    private let failureLimit = 2

    /// Fails init when the system model isn't ready (unsupported device, Apple Intelligence
    /// off, model still downloading) so the factory can fall back cleanly.
    init?() {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        self.session = LanguageModelSession(instructions: Self.instructions)
    }

    func interpret(_ glosses: [String]) async -> String? {
        guard isUsable else { return nil }
        // One or two glosses carry too little structure to translate; showing them raw is
        // more honest than inventing a sentence around them.
        guard glosses.count >= 2 else { return nil }

        let prompt = "Translate this ASL gloss sequence: " + glosses.joined(separator: " ")
        do {
            let response = try await session.respond(to: prompt)
            consecutiveFailures = 0
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.uppercased() != "UNCLEAR" else { return nil }
            return text
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= failureLimit {
                isUsable = false
                log.notice("On-device model reported available but cannot run (\(error.localizedDescription)) — showing glosses instead.")
            }
            return nil
        }
    }
}
