import SwiftUI

/// Interactive grounding exercise player (5-4-3-2-1 technique)
struct LibraryGroundingPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel
    @State private var currentInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Progress header
            progressHeader

            Divider()

            // Main content
            if let grounding = viewModel.groundingInstructions {
                groundingContent(grounding)
            } else {
                fallbackContent
            }

            Divider()

            // Bottom controls
            controlsSection
        }
        .background(SupportTheme.canvas)
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Technique name
            if let technique = viewModel.groundingInstructions?.technique {
                Text(technique.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Sense progress icons
            if let grounding = viewModel.groundingInstructions {
                HStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(Array(grounding.prompts.enumerated()), id: \.offset) { index, prompt in
                        SenseIcon(
                            sense: prompt.sense ?? "general",
                            isCompleted: viewModel.acknowledgedItems.contains(index),
                            color: SupportTheme.accent
                        )
                        .scaleEffect(reduceMotion ? 1 : (index == viewModel.currentGroundingIndex ? 1.1 : 0.85))
                        .animation(reduceMotion ? nil : .spring(response: 0.3), value: viewModel.currentGroundingIndex)
                    }
                }
            }
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Grounding Content

    private func groundingContent(_ grounding: GroundingInstructions) -> some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Current prompt
                if viewModel.currentGroundingIndex < grounding.prompts.count {
                    let prompt = grounding.prompts[viewModel.currentGroundingIndex]
                    currentPromptCard(prompt)
                }

                // Acknowledged items for current sense
                acknowledgedItemsList
            }
            .padding(SupportTheme.Spacing.m)
        }
    }

    private func currentPromptCard(_ prompt: GroundingPrompt) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Sense icon
            Image(systemName: prompt.senseIcon)
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            // Prompt text
            Text(prompt.text)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            // Count indicator (e.g., "Name 5 things")
            if let count = prompt.count {
                Text("Name \(count) things")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Input field
            HStack {
                TextField("What do you notice?", text: $currentInput)
                    .supportField()

                Button {
                    if !currentInput.isEmpty {
                        acknowledgeItem()
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(currentInput.isEmpty ? .secondary : SupportTheme.accent)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Add response")
                }
                .disabled(currentInput.isEmpty)
            }

            // Quick acknowledge button (without text)
            Button {
                acknowledgeItem()
            } label: {
                Text("I noticed something")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .supportCard()
    }

    private var acknowledgedItemsList: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            if !viewModel.groundingResponses.filter({ !$0.isEmpty }).isEmpty {
                Text("What you noticed:")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                ForEach(Array(viewModel.groundingResponses.enumerated()), id: \.offset) { index, response in
                    if !response.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SupportTheme.accent)
                            Text(response)
                                .font(.body)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(viewModel.exercise.description)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: SupportTheme.Spacing.l) {
            // Previous
            Button {
                if viewModel.currentGroundingIndex > 0 {
                    viewModel.currentGroundingIndex -= 1
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Previous step")
            }
            .disabled(viewModel.currentGroundingIndex == 0)

            Spacer()

            // Step counter
            if let grounding = viewModel.groundingInstructions {
                Text("Step \(viewModel.currentGroundingIndex + 1) of \(grounding.prompts.count)")
                    .font(.headline)
            }

            Spacer()

            // Next / Complete
            Button {
                if let grounding = viewModel.groundingInstructions,
                   viewModel.currentGroundingIndex >= grounding.prompts.count - 1 {
                    viewModel.completeExercise()
                } else {
                    viewModel.advanceGrounding()
                }
            } label: {
                Image(systemName: viewModel.currentGroundingIndex >= (viewModel.groundingInstructions?.prompts.count ?? 1) - 1
                    ? "checkmark.circle.fill"
                    : "chevron.right.circle.fill")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Continue exercise")
            }
        }
        .padding(SupportTheme.Spacing.m)
        .padding(.bottom, SupportTheme.Spacing.m)
    }

    // MARK: - Actions

    private func acknowledgeItem() {
        let index = viewModel.currentGroundingIndex
        if index < viewModel.groundingResponses.count {
            viewModel.groundingResponses[index] = currentInput.isEmpty ? "✓" : currentInput
        }
        currentInput = ""
        viewModel.acknowledgeGroundingItem(at: index)
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
