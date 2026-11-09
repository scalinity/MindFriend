import SwiftUI

/// Journaling exercise player with embedded text fields
struct LibraryJournalingPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel
    @FocusState private var focusedPrompt: Int?
    @State private var currentPromptIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Journaling content
            if let journaling = viewModel.journalingInstructions {
                journalingContent(journaling)
            } else {
                fallbackContent
            }

            // Keyboard toolbar appears automatically
        }
        .background(SupportTheme.canvas)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Progress dots
            if let journaling = viewModel.journalingInstructions {
                ProgressDots(
                    total: journaling.prompts.count,
                    current: currentPromptIndex,
                    activeColor: SupportTheme.accent
                )
            }

            // Title
            Text("Journal Prompts")
                .font(.headline)
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Journaling Content

    private func journalingContent(_ journaling: JournalingInstructions) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SupportTheme.Spacing.l) {
                    // Prompts
                    ForEach(Array(journaling.prompts.enumerated()), id: \.offset) { index, prompt in
                        promptCard(prompt: prompt, index: index)
                            .id(index)
                    }

                    // Reflection questions
                    if let questions = journaling.reflectionQuestions, !questions.isEmpty {
                        reflectionSection(questions: questions)
                    }

                    // Complete button
                    completeButton
                        .padding(.bottom, SupportTheme.Spacing.xl)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .onChange(of: focusedPrompt) { _, newValue in
                if let index = newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func promptCard(prompt: JournalingPrompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Category badge
            if let category = prompt.category {
                Text(category.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SupportTheme.accent)
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.surface)
                    .clipShape(Capsule())
            }

            // Prompt text
            Text(prompt.text)
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)

            // Text editor
            TextEditor(text: binding(for: index))
                .frame(minHeight: 120)
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.separator)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .focused($focusedPrompt, equals: index)
                .onChange(of: focusedPrompt) { _, newValue in
                    if newValue == index {
                        currentPromptIndex = index
                    }
                }

            // Character count
            Text("\(viewModel.journalResponses[safe: index]?.count ?? 0) characters")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .stroke(focusedPrompt == index ? SupportTheme.accent : Color.clear, lineWidth: 2)
        )
    }

    private func reflectionSection(questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Reflection Questions")
                .font(.headline)
                .foregroundStyle(SupportTheme.textSecondary)

            ForEach(questions, id: \.self) { question in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(SupportTheme.accent)

                    Text(question)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
    }

    private var completeButton: some View {
        Button {
            // Save drafts before completing
            saveDrafts()
            viewModel.completeExercise()
        } label: {
            Text("Complete Journal Entry")
        }
        .buttonStyle(.supportPrimary)
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "pencil.and.scribble")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(viewModel.exercise.description)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            // Single text editor for unstructured journaling
            TextEditor(text: Binding(
                get: { viewModel.journalResponses.first ?? "" },
                set: { newValue in
                    if viewModel.journalResponses.isEmpty {
                        viewModel.journalResponses = [newValue]
                    } else {
                        viewModel.journalResponses[0] = newValue
                    }
                }
            ))
            .frame(height: 200)
            .padding(SupportTheme.Spacing.s)
            .background(SupportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .padding(.horizontal, SupportTheme.Spacing.m)

            Button {
                viewModel.completeExercise()
            } label: {
                Text("Done")
            }
            .buttonStyle(.supportPrimary)
            .padding(.horizontal, SupportTheme.Spacing.m)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.journalResponses[safe: index] ?? "" },
            set: { newValue in
                while viewModel.journalResponses.count <= index {
                    viewModel.journalResponses.append("")
                }
                viewModel.journalResponses[index] = newValue
            }
        )
    }

    private func saveDrafts() {
        // Save to UserDefaults for recovery
        let key = "journal_draft_\(viewModel.exercise.id)"
        if let data = try? JSONEncoder().encode(viewModel.journalResponses) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
