import SwiftUI

// MARK: - Coping Kit Completion View

struct CopingKitCompletionView: View {
    @ObservedObject var viewModel: CopingKitsViewModel
    let kit: CopingKit

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFeedback: Bool?
    @State private var feedbackComment: String = ""
    @State private var showingCelebration = false

    var body: some View {
        VStack(spacing: 24) {
            ScrollView {
                VStack(spacing: 32) {
                    // Celebration icon
                    celebrationIcon

                    // Success message
                    successMessage

                    // Stats
                    statsSection

                    // Feedback section
                    if selectedFeedback == nil {
                        feedbackSection
                    } else {
                        // Feedback submitted
                        feedbackSubmittedSection
                    }
                }
                .padding(20)
            }

            // Bottom action
            if selectedFeedback != nil || viewModel.completionResult != nil {
                doneButton
            }
        }
        .onAppear {
            showingCelebration = true
        }
    }

    // MARK: - Celebration Icon

    private var celebrationIcon: some View {
        ZStack {
            // Pulsing background
            Circle()
                .fill(Color.pink.opacity(0.1))
                .frame(width: 120, height: 120)
                .scaleEffect(showingCelebration ? 1.2 : 1.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showingCelebration)

            Circle()
                .fill(Color.pink.opacity(0.2))
                .frame(width: 90, height: 90)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.pink)
        }
        .padding(.top, 20)
    }

    // MARK: - Success Message

    private var successMessage: some View {
        VStack(spacing: 12) {
            Text("Well done!")
                .font(.title)
                .fontWeight(.bold)

            Text(kit.contextTag.completionMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 16) {
            if let result = viewModel.completionResult {
                // XP gained
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)

                    Text("+\(result.xpAwarded) XP earned")
                        .fontWeight(.semibold)

                    Spacer()
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Streak info
                if result.streakIncremented {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)

                        Text("Streak maintained!")
                            .fontWeight(.semibold)

                        Spacer()

                        Text("\(result.streakIncremented ? "1" : "0") day")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Level up
                if let levelUp = result.levelUp {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.green)

                        Text("Level \(levelUp.oldLevel) → \(levelUp.newLevel)!")
                            .fontWeight(.semibold)

                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                // Default stats
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)

                    Text("\(kit.formattedDuration) completed")
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(kit.stepsCount) steps")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        VStack(spacing: 16) {
            Text("Was this helpful?")
                .font(.headline)

            HStack(spacing: 32) {
                Button {
                    selectedFeedback = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Yes")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    selectedFeedback = false
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Not really")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }

            // Comment field (optional)
            if selectedFeedback == false {
                TextField("How could we improve?", text: $feedbackComment)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Feedback Submitted Section

    private var feedbackSubmittedSection: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Thanks for your feedback!")
                .fontWeight(.medium)

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            Task {
                // Submit feedback if selected
                if let feedback = selectedFeedback {
                    try? await viewModel.service.submitFeedback(
                        kitId: kit.id,
                        helpful: feedback,
                        comment: feedbackComment.isEmpty ? nil : feedbackComment
                    )
                }

                viewModel.dismissCompletion()
                dismiss()
            }
        } label: {
            Text("Done")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.pink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Context Tag Extension

extension CopingKitContextTag {
    var completionMessage: String {
        switch self {
        case .anxiety:
            return "You took a moment to ground yourself and find calm. That's a powerful act of self-care."
        case .stress:
            return "You've given your nervous system a chance to reset. Remember, it's okay to take breaks."
        case .sadness:
            return "You showed up for yourself, even when it was hard. That's what matters most."
        case .sleep:
            return "Your mind and body are now better prepared for rest. Sleep well."
        case .focus:
            return "You've cleared mental space and centered yourself. Now you're ready to focus."
        case .crisis:
            return "You got through this moment. Remember, this feeling will pass. You're not alone."
        }
    }
}

// MARK: - Preview

#Preview {
    let viewModel = CopingKitsViewModel.preview()
    let kit = viewModel.availableKits[0]
    return CopingKitCompletionView(viewModel: viewModel, kit: kit)
}
