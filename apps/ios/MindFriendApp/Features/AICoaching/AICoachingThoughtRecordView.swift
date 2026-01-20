import SwiftUI

// MARK: - Thought Record Editor View (Reframe Mode)

struct AICoachingThoughtRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AICoachingThoughtRecordViewModel()

    let onSave: ((ThoughtRecord) -> Void)?

    @State private var currentStep: ThoughtRecordStep = .activatingEvent

    init(onSave: ((ThoughtRecord) -> Void)? = nil) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator

                // Step content
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case .activatingEvent:
                            activatingEventStep
                        case .automaticThoughts:
                            automaticThoughtsStep
                        case .emotions:
                            emotionsStep
                        case .distortions:
                            distortionsStep
                        case .evidence:
                            evidenceStep
                        case .reframing:
                            reframingStep
                        case .outcome:
                            outcomeStep
                        }
                    }
                    .padding()
                }

                // Navigation buttons
                navigationButtons
            }
            .navigationTitle("Thought Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if currentStep != .activatingEvent {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save Draft") {
                            saveDraft()
                        }
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(ThoughtRecordStep.allCases, id: \.self) { step in
                    Rectangle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.orange : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }

            Text(stepTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var stepTitle: String {
        switch currentStep {
        case .activatingEvent: return "What happened?"
        case .automaticThoughts: return "What did you think?"
        case .emotions: return "How did you feel?"
        case .distortions: return "Identify patterns"
        case .evidence: return "Examine the evidence"
        case .reframing: return "Find balance"
        case .outcome: return "Your new perspective"
        }
    }

    // MARK: - Step Views

    private var activatingEventStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happened?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Describe the situation or event that triggered your current mood. Be specific about when, where, and what happened.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.activatingEvent)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Example prompts
            VStack(alignment: .leading, spacing: 8) {
                Text("Need a starting point?")
                    .font(.subheadline)
                    .fontWeight(.medium)

                PromptChip(text: "I received critical feedback at work") {
                    viewModel.activatingEvent = "I received critical feedback at work"
                }

                PromptChip(text: "I compared myself to someone else's success") {
                    viewModel.activatingEvent = "I compared myself to someone else's success"
                }

                PromptChip(text: "I made a mistake in front of others") {
                    viewModel.activatingEvent = "I made a mistake in front of others"
                }
            }
        }
    }

    private var automaticThoughtsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What thoughts ran through your mind?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("List the automatic thoughts that came up. Don't judge them - just observe what your mind was saying.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(viewModel.automaticThoughts.enumerated()), id: \.offset) { index, thought in
                HStack {
                    TextEditor(text: Binding(
                        get: { thought },
                        set: { viewModel.automaticThoughts[index] = $0 }
                    ))
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        viewModel.automaticThoughts.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            Button {
                viewModel.automaticThoughts.append("")
            } label: {
                Label("Add Another Thought", systemImage: "plus.circle")
            }
        }
    }

    private var emotionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How did you feel?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select the emotions you experienced and rate their intensity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(["Anxious", "Sad", "Angry", "Frustrated", "Disappointed", "Overwhelmed", "Ashamed", "Guilty"], id: \.self) { emotion in
                    EmotionRow(
                        emotion: emotion,
                        intensity: viewModel.emotionIntensities[emotion] ?? .medium,
                        onIntensityChange: { intensity in
                            viewModel.emotionIntensities[emotion] = intensity
                        }
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var distortionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which patterns do you notice?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Cognitive distortions are ways our mind tries to make sense of a situation. Which of these might be present?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(CognitiveDistortion.allCases) { distortion in
                    DistortionToggle(
                        distortion: distortion,
                        isSelected: viewModel.identifiedDistortions.contains(distortion)
                    ) {
                        if viewModel.identifiedDistortions.contains(distortion) {
                            viewModel.identifiedDistortions.removeAll { $0 == distortion }
                        } else {
                            viewModel.identifiedDistortions.append(distortion)
                        }
                    }
                }
            }
        }
    }

    private var evidenceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Examine the evidence")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Let's look at the evidence for and against your automatic thoughts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Evidence FOR the thought:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $viewModel.evidenceForThoughts)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Evidence AGAINST the thought:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $viewModel.evidenceAgainstThoughts)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var reframingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find a balanced perspective")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Based on the evidence, what would be a more balanced thought?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("A more balanced thought:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $viewModel.balancedThought)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Alternative perspective:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $viewModel.alternativePerspective)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // AI suggestions if available
            if let suggestion = viewModel.aiSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Suggestion:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)

                    Text(suggestion)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var outcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your new perspective")
                .font(.title2)
                .fontWeight(.semibold)

            Text("How do you feel now after going through this process?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Emotions after reframing:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    ForEach(["Calmer", "Hopeful", "Clearer", "More Balanced"], id: \.self) { emotion in
                        OutcomeEmotionButton(
                            emotion: emotion,
                            isSelected: viewModel.outcomeEmotions.contains(emotion)
                        ) {
                            if viewModel.outcomeEmotions.contains(emotion) {
                                viewModel.outcomeEmotions.removeAll { $0 == emotion }
                            } else {
                                viewModel.outcomeEmotions.append(emotion)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("What did you learn?")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $viewModel.lessonLearned)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if !currentStep.isFirst {
                Button {
                    goToPreviousStep()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if currentStep.isLast {
                Button {
                    completeAndSave()
                } label: {
                    Text("Complete")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canComplete)
            } else {
                Button {
                    goToNextStep()
                } label: {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canContinue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var canContinue: Bool {
        switch currentStep {
        case .activatingEvent: return !viewModel.activatingEvent.isEmpty
        case .automaticThoughts: return viewModel.automaticThoughts.contains { !$0.isEmpty }
        case .emotions: return !viewModel.emotionIntensities.isEmpty
        case .distortions: return !viewModel.identifiedDistortions.isEmpty
        case .evidence: return true // Optional
        case .reframing: return !viewModel.balancedThought.isEmpty
        case .outcome: return true // Optional
        }
    }

    private var canComplete: Bool {
        !viewModel.balancedThought.isEmpty
    }

    private func goToNextStep() {
        guard let nextStep = ThoughtRecordStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation {
            currentStep = nextStep
        }
    }

    private func goToPreviousStep() {
        guard let prevStep = ThoughtRecordStep(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation {
            currentStep = prevStep
        }
    }

    private func saveDraft() {
        // Save as draft
        dismiss()
    }

    private func completeAndSave() {
        Task {
            if let record = await viewModel.createThoughtRecord() {
                onSave?(record)
                dismiss()
            }
        }
    }
}

// MARK: - Supporting Views

struct PromptChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmotionRow: View {
    let emotion: String
    let intensity: EmotionIntensity
    let onIntensityChange: (EmotionIntensity) -> Void

    var body: some View {
        HStack {
            Text(emotion)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 8) {
                ForEach([EmotionIntensity.low, .medium, .high], id: \.self) { level in
                    Button {
                        onIntensityChange(level)
                    } label: {
                        Text(level.emoji)
                            .font(.title3)
                            .opacity(intensity == level ? 1 : 0.3)
                    }
                }
            }
        }
    }
}

struct DistortionToggle: View {
    let distortion: CognitiveDistortion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(distortion.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(distortion.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .padding()
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct OutcomeEmotionButton: View {
    let emotion: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emotion)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.green.opacity(0.2) : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .green : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thought Record Step Enum

enum ThoughtRecordStep: Int, CaseIterable {
    case activatingEvent = 0
    case automaticThoughts = 1
    case emotions = 2
    case distortions = 3
    case evidence = 4
    case reframing = 5
    case outcome = 6

    var isFirst: Bool { self == .activatingEvent }
    var isLast: Bool { self == .outcome }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AICoachingThoughtRecordView()
}
#endif
