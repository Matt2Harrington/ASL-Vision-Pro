import AVFoundation
import Foundation
import OSLog

/// Speaks recognized signing aloud, so the app can be used without looking at the screen.
///
/// This is the Deaf→hearing direction: the wearer signs, the device speaks for them. That
/// makes it materially more committal than showing text. A caption a hearing person misreads
/// is their error; a spoken word puts words in the signer's mouth. Three things follow from
/// that, and they are the reason this class exists rather than a bare synthesizer call:
///
///   * The confidence bar for speaking is deliberately higher than for displaying.
///   * Nothing is spoken twice in quick succession, so a held sign doesn't stutter.
///   * Speech can always be silenced immediately, mid-utterance.
///
/// Uses `AVSpeechSynthesizer`, which is on-device — consistent with the rest of the pipeline,
/// nothing is uploaded to synthesize.
@MainActor
@Observable
final class SignSpeaker {
    /// Off by default. Speaking aloud is a deliberate act, not something to start doing on
    /// a user's behalf the first time recognition happens to fire.
    var isEnabled = false

    /// How sure the recognizer must be before a word is spoken. Higher than the on-screen
    /// threshold: a wrong caption can be read past, a wrong word cannot be unsaid.
    var threshold: Float = 0.9

    enum Mode: String, CaseIterable {
        /// Speak each sign as it is recognized — responsive, but reads as a word list.
        case word
        /// Wait for a pause, then speak the assembled English sentence — natural, but lags.
        case sentence

        var title: String { self == .word ? "Each sign" : "Sentences" }
    }
    /// Defaults to speaking each sign, since sentence assembly is behind a setting. Selecting
    /// sentence mode without that setting on would leave voice output silent, because nothing
    /// would ever assemble a sentence to speak.
    var mode: Mode = .word

    private(set) var isSpeaking = false
    /// Most recent utterance, for the UI to show what was said.
    private(set) var lastSpoken: String?
    /// How many things have actually been said. `lastSpoken` alone can't distinguish a
    /// suppressed repeat from a fresh utterance of the same text, which makes the repeat
    /// guard unobservable — to the UI and to tests alike.
    private(set) var utteranceCount = 0

    private let log = Logger(subsystem: "ASLVisionPro", category: "Speaker")
    private let synthesizer = AVSpeechSynthesizer()
    /// Injected rather than reached for, so a test can vary the flag without mutating global
    /// state that other tests then inherit.
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }
    private var lastText: String?
    private var lastSpokenAt = Date.distantPast
    /// A sign held across several windows re-fires recognition; without this the same word is
    /// spoken repeatedly.
    private let repeatWindow: TimeInterval = 2.5

    // MARK: - Speaking

    /// Speak one recognized sign. Ignored unless it clears the confidence bar.
    func speak(sign: String, confidence: Float) {
        guard isEnabled, mode == .word else { return }
        guard confidence >= threshold else { return }
        guard sign != CoreMLSignRecognizer.restLabel else { return }
        utter(sign.replacingOccurrences(of: "-", with: " "))
    }

    /// Speak an assembled English sentence. Sentence mode only, so the two modes never
    /// double up on the same utterance.
    func speak(sentence: String) {
        guard isEnabled, mode == .sentence, settings.sentencesEnabled else { return }
        utter(sentence)
    }

    private func utter(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Suppress an immediate repeat, but allow the same phrase again later — someone may
        // genuinely sign the same thing twice.
        if trimmed == lastText, Date().timeIntervalSince(lastSpokenAt) < repeatWindow { return }
        lastText = trimmed
        lastSpokenAt = Date()

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)

        isSpeaking = true
        lastSpoken = trimmed
        utteranceCount += 1
        log.info("Spoke: \(trimmed, privacy: .public)")
    }

    /// Stop immediately, mid-word. Someone who realizes the app is about to say the wrong
    /// thing on their behalf needs it to stop now, not at the end of the sentence.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Let the same phrase be spoken again straight away — used when the user resets, so a
    /// fresh attempt isn't swallowed as a repeat.
    func reset() {
        lastText = nil
        lastSpokenAt = .distantPast
        lastSpoken = nil
        utteranceCount = 0
    }

    #if os(iOS)
    private var sessionConfigured = false
    /// Playback that ducks other audio rather than stopping it, and doesn't silence the app
    /// when the ring switch is off — this is assistive output, not media.
    private func configureAudioSession() {
        guard !sessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            sessionConfigured = true
        } catch {
            log.error("Audio session setup failed: \(error.localizedDescription)")
        }
    }
    #else
    private func configureAudioSession() {}
    #endif
}
