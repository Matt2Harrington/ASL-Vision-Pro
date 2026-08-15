import Foundation

/// Maps English text to a sequence of ASL glosses for display.
///
/// **This produces Signed-English-order glosses, not fluent ASL.** Real ASL has
/// topic-comment structure, spatial grammar, and non-manual markers that a word-level mapping
/// cannot express (RECOGNITION_APPROACH.md §Level 3, in reverse). What it does do is degrade
/// gracefully: the failure mode is awkward ordering, not wrong meaning — unlike recognition,
/// where a mistake invents words the person never said.
///
/// Two behaviours make it useful rather than brittle:
///   • **Function-word dropping.** ASL omits English articles/copulas ("the", "is", "to"),
///     so dropping them gets closer to ASL than a literal word-for-word rendering.
///   • **Fingerspelling fallback.** Unknown words are spelled letter-by-letter — exactly what
///     a human interpreter does for names and out-of-vocabulary terms.
struct GlossTranslator {
    private let catalog: SignCatalog

    /// English words ASL typically does not sign. Dropping them is closer to ASL than
    /// rendering them literally.
    private static let droppedWords: Set<String> = [
        "a", "an", "the", "is", "are", "am", "was", "were", "be", "been", "being",
        "to", "of", "at", "as", "do", "does", "did", "will", "would", "shall",
    ]

    /// Common surface forms that map onto a single gloss.
    private static let synonyms: [String: String] = [
        "hi": "HELLO", "hey": "HELLO",
        "thanks": "THANK-YOU", "thankyou": "THANK-YOU",
        "bye": "GOODBYE", "farewell": "GOODBYE",
        "restroom": "BATHROOM", "toilet": "BATHROOM",
        "yeah": "YES", "yep": "YES", "yup": "YES",
        "nope": "NO", "nah": "NO",
        "assist": "HELP", "aid": "HELP",
        "understood": "UNDERSTAND", "comprehend": "UNDERSTAND",
        "repeat": "AGAIN", "sorry": "SORRY", "apologize": "SORRY",
    ]

    init(catalog: SignCatalog = .shared) {
        self.catalog = catalog
    }

    /// One unit of output — either a known sign or a word to fingerspell.
    enum Token: Identifiable, Hashable {
        case sign(SignEntry)
        case fingerspell(String)

        var id: String {
            switch self {
            case .sign(let e):        return "sign-\(e.gloss)"
            case .fingerspell(let w): return "fs-\(w)"
            }
        }

        var display: String {
            switch self {
            case .sign(let e):        return e.gloss
            case .fingerspell(let w): return w.uppercased()
            }
        }
    }

    func translate(_ english: String) -> [Token] {
        words(in: english).compactMap { word in
            if Self.droppedWords.contains(word) { return nil }
            let candidate = Self.synonyms[word] ?? word.uppercased()
            if let entry = catalog.entry(for: candidate) {
                return .sign(entry)
            }
            // Try a naive plural/possessive strip before giving up.
            if candidate.hasSuffix("S"), let entry = catalog.entry(for: String(candidate.dropLast())) {
                return .sign(entry)
            }
            return .fingerspell(word)
        }
    }

    /// Fraction of tokens that mapped to real signs — drives an honest coverage indicator in
    /// the UI, so the user can see when output is mostly fingerspelling.
    func coverage(of tokens: [Token]) -> Double {
        guard !tokens.isEmpty else { return 0 }
        let signs = tokens.filter { if case .sign = $0 { return true } else { return false } }
        return Double(signs.count) / Double(tokens.count)
    }

    private func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
