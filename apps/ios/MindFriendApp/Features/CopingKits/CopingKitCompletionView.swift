import SwiftUI

// MARK: - Coping Kit Completion View

struct CopingKitCompletionView: View {
    @ObservedObject var viewModel: CopingKitsViewModel
    let kit: CopingKit

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFeedback: Bool?
    @State private var feedbackComment: String = ""

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.xl) {
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
                .padding(SupportTheme.Spacing.m)
            }

            // Bottom action
            if selectedFeedback != nil || viewModel.completionResult != nil {
                doneButton
            }
        }
        .supportSheet()
    }

    // MARK: - Celebration Icon

    private var celebrationIcon: some View {
        CelebrationEmblem(.symbol("checkmark.circle.fill"))
            .celebrationReveal()
            .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Success Message

    private var successMessage: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Text("Well done")
                .font(.title)
                .fontWeight(.bold)

            Text(kit.contextTag.completionMessage)
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            if let result = viewModel.completionResult {
                // XP gained
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(SupportTheme.accent)

                    Text("+\(result.xpAwarded) XP earned")
                        .fontWeight(.semibold)

                    Spacer()
                }
                .supportCard()



                // Level up
                if let levelUp = result.levelUp {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(SupportTheme.accent)

                        Text("Level \(levelUp.oldLevel) → \(levelUp.newLevel)")
                            .fontWeight(.semibold)

                        Spacer()
                    }
                    .supportCard()
                }
            } else {
                // Default stats
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(SupportTheme.accent)

                    Text("\(kit.formattedDuration) completed")
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(kit.stepsCount) steps")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .supportCard()
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Text("Was this helpful?")
                .font(.headline)

            HStack(spacing: SupportTheme.Spacing.xl) {
                Button {
                    selectedFeedback = true
                } label: {
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.largeTitle)
                            .foregroundStyle(SupportTheme.accent)
                        Text("Yes")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    selectedFeedback = false
                } label: {
                    VStack(spacing: SupportTheme.Spacing.xs) {
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
                    .supportField()
                    .padding(.top, SupportTheme.Spacing.xs)
            }
        }
        .supportCard()
    }

    // MARK: - Feedback Submitted Section

    private var feedbackSubmittedSection: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SupportTheme.accent)

            Text("Thanks for your feedback!")
                .fontWeight(.medium)

            Spacer()
        }
        .supportCard()
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            Task {
                // Submit feedback if selected
                if let feedback = selectedFeedback {
                    try? await viewModel.submitFeedback(
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
        }
        .buttonStyle(.supportPrimary)
        .padding(.horizontal, SupportTheme.Spacing.m)
        .padding(.bottom, SupportTheme.Spacing.m)
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

#if DEBUG
#Preview {
    let viewModel = CopingKitsViewModel.preview()
    let kit = viewModel.availableKits[0]
    return CopingKitCompletionView(viewModel: viewModel, kit: kit)
}
#endif
