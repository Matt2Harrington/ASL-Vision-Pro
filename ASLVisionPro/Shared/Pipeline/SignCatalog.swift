import Foundation

/// One entry in the sign dictionary — the shared content model behind both the reference
/// browser (Direction 3) and the tutor's lessons.
///
/// The parameters below are ASL's actual phonological building blocks. Describing signs this
/// way (rather than as opaque video clips) is what lets the tutor give *actionable* feedback
/// — "your handshape is right but the location is wrong" — instead of just a score.
struct SignEntry: Identifiable, Codable, Hashable {
    var id: String { gloss }

    /// ASL gloss convention: CAPS, hyphens for multi-word glosses that are one sign.
    let gloss: String
    /// Plain-English meaning.
    let meaning: String
    /// Handshape name (e.g. "flat B", "closed fist", "index point").
    let handshape: String
    /// Where the sign is made (e.g. "chin", "neutral space", "forehead").
    let location: String
    /// How the hands move (e.g. "arc outward", "tap twice").
    let movement: String
    /// Palm orientation (e.g. "palm down", "palm toward signer").
    let orientation: String
    /// Facial expression / head movement that carries grammar. Often the difference between
    /// minimal pairs, and the part hand-only models miss.
    let nonManual: String?
    /// One-handed vs two-handed.
    let isTwoHanded: Bool
    /// Grouping for lessons and browsing.
    let category: Category

    enum Category: String, Codable, CaseIterable {
        case greetings, courtesy, questions, responses, people
        case feelings, needs, time, places, repair, alphabet

        var title: String {
            switch self {
            case .greetings:  return "Greetings"
            case .courtesy:   return "Courtesy"
            case .questions:  return "Questions"
            case .responses:  return "Responses"
            case .people:     return "People"
            case .feelings:   return "Feelings"
            case .needs:      return "Needs"
            case .time:       return "Time"
            case .places:     return "Places"
            case .repair:     return "Conversation Repair"
            case .alphabet:   return "Fingerspelling"
            }
        }
    }
}

/// Loads and queries the sign catalog. Backed by a bundled JSON so content can grow without
/// code changes — and so the same file can feed lessons, the dictionary, and the data
/// collector's prompts.
@Observable
final class SignCatalog {
    private(set) var entries: [SignEntry] = []

    static let shared = SignCatalog()

    /// `bundle` is injectable because `Bundle.main` in a unit-test process is the test
    /// *runner*, not the test bundle — tests must pass their own bundle to load signs.json.
    init(bundle: Bundle = .main) {
        load(from: bundle)
    }

    private func load(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "signs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SignEntry].self, from: data) else {
            entries = Self.fallback
            return
        }
        entries = decoded
    }

    func entry(for gloss: String) -> SignEntry? {
        entries.first { $0.gloss == gloss }
    }

    func entries(in category: SignEntry.Category) -> [SignEntry] {
        entries.filter { $0.category == category }.sorted { $0.gloss < $1.gloss }
    }

    func search(_ query: String) -> [SignEntry] {
        guard !query.isEmpty else { return entries.sorted { $0.gloss < $1.gloss } }
        let q = query.lowercased()
        return entries
            .filter { $0.gloss.lowercased().contains(q) || $0.meaning.lowercased().contains(q) }
            .sorted { $0.gloss < $1.gloss }
    }

    /// Glosses for a lesson in a category — feeds `TutorSession`.
    func lesson(for category: SignEntry.Category, limit: Int = 10) -> [String] {
        entries(in: category).prefix(limit).map(\.gloss)
    }

    /// Minimal built-in set so the app is functional if the bundled JSON is missing.
    /// The real catalog lives in `signs.json`.
    private static let fallback: [SignEntry] = [
        SignEntry(gloss: "HELLO", meaning: "hello, hi",
                  handshape: "flat B", location: "forehead",
                  movement: "salute outward from the brow", orientation: "palm forward",
                  nonManual: "friendly expression", isTwoHanded: false, category: .greetings),
        SignEntry(gloss: "THANK-YOU", meaning: "thank you",
                  handshape: "flat B", location: "chin",
                  movement: "move forward and down from the chin", orientation: "palm inward",
                  nonManual: nil, isTwoHanded: false, category: .courtesy),
        SignEntry(gloss: "PLEASE", meaning: "please",
                  handshape: "flat B", location: "chest",
                  movement: "circle on the chest", orientation: "palm inward",
                  nonManual: nil, isTwoHanded: false, category: .courtesy),
    ]
}
