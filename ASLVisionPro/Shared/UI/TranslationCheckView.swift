import SwiftUI

/// On-device check for the gloss → English stage.
///
/// This exists because the translation half cannot be evaluated on a Mac: the simulator has
/// no Apple Intelligence model assets, so every request fails there. Running it as a screen
/// means the question "is prompting good enough, or do we need a trained adapter?" can be
/// answered on the actual device in a couple of minutes, rather than through Xcode's test
/// runner and console logs.
struct TranslationCheckView: View {
    @State private var interpreter: GlossInterpreting = GlossInterpreterFactory.make()
    @State private var results: [Row] = []
    @State private var customInput = ""
    @State private var isRunning = false
    @FocusState private var inputFocused: Bool

    /// Sequences chosen to cover the cases that actually stress the prompt: fingerspelled
    /// names, dropped function words, ASL question order, and negation.
    private static let samples: [[String]] = [
        ["ME", "NAME", "M-A-T-T"],
        ["YOU", "WANT", "COFFEE"],
        ["HELLO", "NICE", "MEET", "YOU"],
        ["ME", "NOT", "UNDERSTAND", "PLEASE", "AGAIN"],
        ["BATHROOM", "WHERE"],
        ["ME", "DEAF", "YOU", "HEARING"],
    ]

    struct Row: Identifiable {
        let id = UUID()
        let glosses: [String]
        let english: String?
        let milliseconds: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                status
                customSection
                if !results.isEmpty { resultsSection }
            }
            .padding(24)
        }
        // Swiping the list down dismisses the keyboard, and tapping outside the field does
        // too — without these the field traps the keyboard with no way to close it.
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { inputFocused = false }
        .navigationTitle("Translation Check")
    }

    // MARK: - Status

    private var status: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconBadge(symbol: "brain", tint: Theme.Accent.listen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Language model").font(.headline)
                        Text(interpreter.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await runSamples() }
                } label: {
                    Label(isRunning ? "Running…" : "Run \(Self.samples.count) samples",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRunning)
            }
        }
    }

    // MARK: - Custom input

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Try your own")
            CardSurface {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("ME NAME M-A-T-T", text: $customInput)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($inputFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            inputFocused = false
                            Task { await runCustom() }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.innerRadius))

                    Button {
                        inputFocused = false
                        Task { await runCustom() }
                    } label: {
                        Label("Translate", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)

                    Text("Space-separated glosses. Hyphens mark one sign (THANK-YOU) or fingerspelling (M-A-T-T).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Results", trailing: "\(results.count)")
            ForEach(results) { row in
                CardSurface(padding: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.glosses.joined(separator: " "))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)

                        if let english = row.english {
                            Text(english)
                                .font(.title3.weight(.medium))
                        } else {
                            // Declining is a designed outcome, not a crash — label it as such
                            // so a blank line isn't read as a failure.
                            Label("Declined — glosses would be shown instead",
                                  systemImage: "minus.circle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }

                        Text("\(row.milliseconds) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Running

    private func runSamples() async {
        isRunning = true
        results = []
        for glosses in Self.samples {
            results.append(await translate(glosses))
        }
        isRunning = false
    }

    private func runCustom() async {
        let glosses = customInput
            .uppercased()
            .split(separator: " ")
            .map(String.init)
        guard !glosses.isEmpty else { return }
        isRunning = true
        results.insert(await translate(glosses), at: 0)
        isRunning = false
    }

    private func translate(_ glosses: [String]) async -> Row {
        let start = Date()
        let english = await interpreter.interpret(glosses)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return Row(glosses: glosses, english: english, milliseconds: ms)
    }
}
