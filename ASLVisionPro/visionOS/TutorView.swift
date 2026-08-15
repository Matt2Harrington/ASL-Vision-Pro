import SwiftUI

/// ASL Tutor screen: shows the target sign, live feedback on the learner's attempt, and
/// lesson progress. The learner's own hands are visible through passthrough, so the UI
/// deliberately stays out of the centre of the view.
struct TutorView: View {
    @State private var session: TutorSession

    init(lesson: [String]) {
        // visionOS drives the tutor from the wearer's own 3D hand joints — no entitlement.
        // The verifier comes from the shared factory so a bundled model is picked up
        // automatically, same as the recognizer.
        _session = State(initialValue: TutorSession(lesson: lesson,
                                                     source: HandTrackingSource(),
                                                     verifier: RecognizerFactory.makeVerifier()))
    }

    var body: some View {
        VStack(spacing: 28) {
            header

            if let target = session.currentTarget {
                targetCard(target)
                feedbackArea
            } else {
                completionCard
            }

            controls
        }
        .padding(40)
        .frame(minWidth: 620)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("ASL Tutor")
                .font(.largeTitle.weight(.semibold))
            ProgressView(value: session.progress)
                .frame(maxWidth: 360)
            Text("\(session.correctCount) correct · \(session.attemptCount) attempts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func targetCard(_ target: String) -> some View {
        VStack(spacing: 10) {
            Text("Sign this")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(target)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var feedbackArea: some View {
        if let attempt = session.lastAttempt {
            VStack(spacing: 10) {
                Text(attempt.feedback.message)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color(for: attempt.feedback))

                // Confidence meter — makes "close" legible rather than abstract.
                ProgressView(value: Double(attempt.score))
                    .tint(color(for: attempt.feedback))
                    .frame(maxWidth: 260)

                if let confused = attempt.confusedWith, !attempt.isCorrect {
                    Text("That looked more like \(confused)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: attempt.score)
        } else {
            Text("Make the sign with your hands")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var completionCard: some View {
        VStack(spacing: 12) {
            Text("Lesson complete")
                .font(.title.weight(.semibold))
            Text("\(session.correctCount) of \(session.attemptCount) attempts correct")
                .foregroundStyle(.secondary)
            Text("\(Int(session.accuracy * 100))% accuracy")
                .font(.title3)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button("Skip") { session.skip() }
                .disabled(session.currentTarget == nil)
            Button(session.isRunning ? "Pause" : "Resume") {
                session.isRunning ? session.stop() : session.start()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func color(for feedback: SignAttempt.Feedback) -> Color {
        switch feedback {
        case .excellent: return .green
        case .good:      return .mint
        case .close:     return .orange
        case .tryAgain:  return .red
        }
    }
}
