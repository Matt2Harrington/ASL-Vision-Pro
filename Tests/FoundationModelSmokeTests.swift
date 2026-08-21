import XCTest

/// Exercises the real on-device language model with realistic gloss sequences and prints what
/// it produces. Not an assertion of quality — model output varies — but it answers the
/// question "does the translation half actually work yet?" without any trained recognizer or
/// downloaded dataset.
///
/// Skips cleanly when Apple Intelligence isn't available on the running device.
final class FoundationModelSmokeTests: XCTestCase {

    func testTranslatesRealisticGlossSequences() async throws {
        guard #available(iOS 26.0, visionOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Foundation Models needs OS 26")
        }
        guard let interpreter = FoundationModelGlossInterpreter() else {
            throw XCTSkip("On-device model unavailable (Apple Intelligence off or downloading)")
        }

        let samples: [[String]] = [
            ["ME", "NAME", "M-A-T-T"],
            ["YOU", "WANT", "COFFEE"],
            ["HELLO", "NICE", "MEET", "YOU"],
            ["ME", "NOT", "UNDERSTAND", "PLEASE", "AGAIN"],
            ["BATHROOM", "WHERE"],
            ["ME", "DEAF", "YOU", "HEARING"],
        ]

        print("\n=== on-device gloss → English ===")
        for glosses in samples {
            let english = await interpreter.interpret(glosses)
            print("  \(glosses.joined(separator: " "))")
            print("    → \(english ?? "(declined)")")
        }
        print("=== end ===\n")
    }
}
