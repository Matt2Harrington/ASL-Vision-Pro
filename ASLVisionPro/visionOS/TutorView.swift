import SwiftUI

/// ASL Tutor. The learner's own hands are the real subject here, so the UI stays out of the
/// way: one large target sign, a single clear feedback line, and controls parked at the
/// bottom. Everything else is chrome and is deliberately quiet.
struct TutorView: View {
    @State private var session: TutorSession
    private let catalog = SignCatalog.shared

    init(lesson: [String]) {
        // Wearer's own 3D hand joints — no entitlement. Verifier comes from the shared
        // factory so a bundled model is picked up automatically.
        _session = State(initialValue: TutorSession(lesson: lesson,
                                                     source: HandTrackingSource(),
                                                     verifier: RecognizerFactory.makeVerifier()))
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            if let target = session.currentTarget {
                practice(target)
            } else {
                summary
            }

            controls
        }
        .padding(40)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    // MARK: - Progress

    private var progressBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Practice").font(.headline)
                Spacer()
                Text("\(session.correctCount) of \(session.attemptCount) correct")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()   // stops the count jittering as it updates
            }
            ProgressView(value: session.progress)
                .tint(.blue)
        }
        .padding(.bottom, 30)
    }

    // MARK: - Practice

    private func practice(_ target: String) -> some View {
        VStack(spacing: 22) {
            Text("Sign this")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)

            Text(target)
                .font(.system(size: 68, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.smooth, value: target)

            // How the sign is formed, straight from the catalog — the learner shouldn't have
            // to leave practice to look it up.
            if let entry = catalog.entry(for: target) {
                HStack(spacing: 22) {
                    hint("Hand", entry.handshape)
                    hint("Where", entry.location)
                    hint("Move", entry.movement)
                }
                .padding(.top, 2)
            }

            feedback
                .frame(height: 96)   // reserved so the layout doesn't jump between states
        }
        .frame(maxHeight: .infinity)
    }

    private func hint(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 190)
    }

    @ViewBuilder
    private var feedback: some View {
        if let attempt = session.lastAttempt {
            VStack(spacing: 10) {
                Label(attempt.feedback.message, systemImage: icon(for: attempt.feedback))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color(for: attempt.feedback))

                Capsule()
                    .fill(.quaternary)
                    .frame(width: 260, height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color(for: attempt.feedback))
                            .frame(width: 260 * CGFloat(max(0.02, min(1, attempt.score))), height: 8)
                    }
                    .animation(.smooth, value: attempt.score)

                if let confused = attempt.confusedWith, !attempt.isCorrect {
                    Text("That looked more like \(confused)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            Text("Make the sign with your hands")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Lesson complete")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Text("\(session.correctCount) of \(session.attemptCount) attempts correct")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(Int(session.accuracy * 100))% accuracy")
                .font(.title2.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                session.isRunning ? session.stop() : session.start()
            } label: {
                Label(session.isRunning ? "Pause" : "Resume",
                      systemImage: session.isRunning ? "pause.fill" : "play.fill")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)

            Button {
                session.skip()
            } label: {
                Label("Skip", systemImage: "forward.fill").frame(minWidth: 110)
            }
            .disabled(session.currentTarget == nil)
        }
        .controlSize(.large)
        .padding(.top, 26)
    }

    // MARK: - Styling

    private func color(for feedback: SignAttempt.Feedback) -> Color {
        switch feedback {
        case .excellent: .green
        case .good:      .mint
        case .close:     .orange
        case .tryAgain:  .red
        }
    }

    private func icon(for feedback: SignAttempt.Feedback) -> String {
        switch feedback {
        case .excellent: "checkmark.seal.fill"
        case .good:      "checkmark.circle.fill"
        case .close:     "arrow.triangle.2.circlepath"
        case .tryAgain:  "arrow.counterclockwise"
        }
    }
}
