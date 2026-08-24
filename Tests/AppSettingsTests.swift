import XCTest

/// The flag decides whether an interpretation layer runs at all, so its default and its
/// persistence both matter.
@MainActor
final class AppSettingsTests: XCTestCase {

    private func makeSettings() -> (AppSettings, UserDefaults) {
        // An isolated suite, so tests never read or write the real app's settings.
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (AppSettings(defaults: defaults), defaults)
    }

    /// Off unless chosen. Sentence assembly costs seconds per phrase and layers an
    /// interpretation over recognition, so the honest default is the raw glosses.
    func testSentencesAreOffByDefault() {
        let (settings, _) = makeSettings()
        XCTAssertFalse(settings.sentencesEnabled)
    }

    func testChoicePersists() {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        AppSettings(defaults: defaults).sentencesEnabled = true
        // A fresh instance reading the same store stands in for a relaunch.
        XCTAssertTrue(AppSettings(defaults: defaults).sentencesEnabled)
    }

    func testTurningOffPersistsToo() {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        AppSettings(defaults: defaults).sentencesEnabled = true
        AppSettings(defaults: defaults).sentencesEnabled = false
        XCTAssertFalse(AppSettings(defaults: defaults).sentencesEnabled)
    }

    /// Sentence speech must stay silent while the feature is off, or selecting that mode
    /// would produce nothing with no explanation.
    func testSpeakerIgnoresSentencesWhileFlagIsOff() {
        let (settings, _) = makeSettings()
        settings.sentencesEnabled = false
        let speaker = SignSpeaker(settings: settings)
        speaker.isEnabled = true
        speaker.mode = .sentence

        speaker.speak(sentence: "My name is Matt.")
        XCTAssertNil(speaker.lastSpoken)
        XCTAssertEqual(speaker.utteranceCount, 0)
    }

    /// Speaking individual signs is unaffected by the flag — that path doesn't assemble
    /// anything.
    func testSpeakingIndividualSignsIsUnaffected() {
        let (settings, _) = makeSettings()
        settings.sentencesEnabled = false
        let speaker = SignSpeaker(settings: settings)
        speaker.isEnabled = true
        speaker.mode = .word

        speaker.speak(sign: "HELLO", confidence: 1.0)
        XCTAssertEqual(speaker.lastSpoken, "HELLO")
    }
}
