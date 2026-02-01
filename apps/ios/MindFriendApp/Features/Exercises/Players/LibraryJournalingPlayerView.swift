import SwiftUI

/// Journaling exercise player with embedded text fields
struct LibraryJournalingPlayerView: View {
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
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Progress dots
            if let journaling = viewModel.journalingInstructions {
                ProgressDots(
                    total: journaling.prompts.count,
                    current: currentPromptIndex,
                    activeColor: .accentColor
                )
            }

            // Title
            Text("Journal Prompts")
                .font(.headline)
        }
        .padding()
    }

    // MARK: - Journaling Content

    private func journalingContent(_ journaling: JournalingInstructions) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
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
                        .padding(.bottom, 32)
                }
                .padding()
            }
            .onChange(of: focusedPrompt) { _, newValue in
                if let index = newValue {
                    withAnimation {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func promptCard(prompt: JournalingPrompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category badge
            if let category = prompt.category {
                Text(category.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Prompt text
            Text(prompt.text)
                .font(.headline)
                .foregroundStyle(.primary)

            // Text editor
            TextEditor(text: binding(for: index))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($focusedPrompt, equals: index)
                .onChange(of: focusedPrompt) { _, newValue in
                    if newValue == index {
                        currentPromptIndex = index
                    }
                }

            // Character count
            Text("\(viewModel.journalResponses[safe: index]?.count ?? 0) characters")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(focusedPrompt == index ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func reflectionSection(questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reflection Questions")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(questions, id: \.self) { question in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)

                    Text(question)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var completeButton: some View {
        Button {
            // Save drafts before completing
            saveDrafts()
            viewModel.completeExercise()
        } label: {
            Text("Complete Journal Entry")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(viewModel.exercise.description)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button {
                viewModel.completeExercise()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

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
