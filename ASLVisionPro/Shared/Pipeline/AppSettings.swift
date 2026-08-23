import Foundation
import Observation

/// Persisted feature flags.
///
/// Kept deliberately small: one place to look, backed by `UserDefaults` so a choice survives
/// relaunch, and `@Observable` so toggling one updates every screen without plumbing.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Assemble recognized signs into English sentences, rather than showing and speaking
    /// them one at a time.
    ///
    /// Off by default, because it is the more speculative path in both directions: it costs
    /// several seconds per phrase, and it layers an interpretation on top of recognition that
    /// can be wrong in ways the raw glosses are not. Someone who wants fluent output can opt
    /// into it; someone who wants to see exactly what was recognized gets that by default.
    var sentencesEnabled: Bool {
        didSet { defaults.set(sentencesEnabled, forKey: Key.sentences) }
    }

    private enum Key {
        static let sentences = "settings.sentencesEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sentencesEnabled = defaults.bool(forKey: Key.sentences)   // false unless set
    }
}
