import SwiftUI

/// Interactive grounding exercise player (5-4-3-2-1 technique)
struct LibraryGroundingPlayerView: View {
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
        .background(Color(.systemBackground))
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 16) {
            // Technique name
            if let technique = viewModel.groundingInstructions?.technique {
                Text(technique.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Sense progress icons
            if let grounding = viewModel.groundingInstructions {
                HStack(spacing: 16) {
                    ForEach(Array(grounding.prompts.enumerated()), id: \.offset) { index, prompt in
                        SenseIcon(
                            sense: prompt.sense ?? "general",
                            isCompleted: viewModel.acknowledgedItems.contains(index),
                            color: prompt.senseColor
                        )
                        .scaleEffect(index == viewModel.currentGroundingIndex ? 1.1 : 0.85)
                        .animation(.spring(response: 0.3), value: viewModel.currentGroundingIndex)
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Grounding Content

    private func groundingContent(_ grounding: GroundingInstructions) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Current prompt
                if viewModel.currentGroundingIndex < grounding.prompts.count {
                    let prompt = grounding.prompts[viewModel.currentGroundingIndex]
                    currentPromptCard(prompt)
                }

                // Acknowledged items for current sense
                acknowledgedItemsList
            }
            .padding()
        }
    }

    private func currentPromptCard(_ prompt: GroundingPrompt) -> some View {
        VStack(spacing: 20) {
            // Sense icon
            Image(systemName: prompt.senseIcon)
                .font(.system(size: 48))
                .foregroundStyle(prompt.senseColor)

            // Prompt text
            Text(prompt.text)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            // Count indicator (e.g., "Name 5 things")
            if let count = prompt.count {
                Text("Name \(count) things")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Input field
            HStack {
                TextField("What do you notice?", text: $currentInput)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if !currentInput.isEmpty {
                        acknowledgeItem()
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(currentInput.isEmpty ? .secondary : Color.accentColor)
                }
                .disabled(currentInput.isEmpty)
            }

            // Quick acknowledge button (without text)
            Button {
                acknowledgeItem()
            } label: {
                Text("I noticed something")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var acknowledgedItemsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.groundingResponses.filter({ !$0.isEmpty }).isEmpty {
                Text("What you noticed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.groundingResponses.enumerated()), id: \.offset) { index, response in
                    if !response.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(viewModel.exercise.description)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 24) {
            // Previous
            Button {
                if viewModel.currentGroundingIndex > 0 {
                    viewModel.currentGroundingIndex -= 1
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title)
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
            }
        }
        .padding()
        .padding(.bottom, 16)
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
