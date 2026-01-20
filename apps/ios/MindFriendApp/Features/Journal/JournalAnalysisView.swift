import SwiftUI

struct JournalAnalysisView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let analysis: JournalAnalysis

    @State private var showingFeedbackFor: CognitiveDistortionInstance?
    @State private var feedbackSubmitted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Emotional themes
                    if !analysis.emotionalThemes.isEmpty {
                        emotionalThemesSection
                    }

                    // Supportive insight
                    supportiveInsightSection

                    // Cognitive distortions
                    if analysis.hasDistortions {
                        cognitiveDistortionsSection
                    }

                    // Suggested reframes (was suggestedActions)
                    if !analysis.suggestedReframes.isEmpty {
                        suggestedReframesSection
                    }

                    // Overall sentiment
                    sentimentSection

                    // Disclaimer
                    disclaimerSection
                }
                .padding()
            }
            .navigationTitle("AI Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $showingFeedbackFor) { distortion in
                DistortionFeedbackSheet(
                    analysisId: analysis.id,
                    distortion: distortion
                ) {
                    feedbackSubmitted = true
                    showingFeedbackFor = nil
                }
                .environmentObject(container)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.purple)
                Text("Your Insights")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("Here's what I noticed in your journal entry. Remember, these are gentle observations to help you reflect, not judgments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emotionalThemesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Emotional Themes", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.pink)

            FlowLayout(spacing: 8) {
                ForEach(analysis.emotionalThemes, id: \.self) { theme in
                    Text(theme.capitalized)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.pink.opacity(0.15))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.pink.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var supportiveInsightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A Gentle Reflection", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text(analysis.supportiveSummary)
                .font(.body)
                .lineSpacing(4)
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var cognitiveDistortionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Thinking Patterns", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("These are common patterns many people experience. Recognizing them is the first step to a more balanced perspective.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(analysis.cognitiveDistortions) { distortion in
                DistortionCard(distortion: distortion) {
                    showingFeedbackFor = distortion
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var suggestedReframesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Things to Consider", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(analysis.suggestedReframes) { reframe in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(reframe.reframe)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sentimentSection: some View {
        HStack {
            Text("Overall Tone:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(analysis.overallSentiment.capitalized)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(sentimentColor)
        }
    }

    private var sentimentColor: Color {
        switch analysis.overallSentiment.lowercased() {
        case "positive", "hopeful", "grateful":
            return .green
        case "negative", "sad", "frustrated", "anxious":
            return .orange
        case "neutral", "reflective":
            return .blue
        default:
            return .secondary
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About these insights")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("This AI analysis is designed to support your self-reflection journey. It's not a substitute for professional mental health support. If you're struggling, please reach out to a counselor or therapist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Supporting Views

struct DistortionCard: View {
    let distortion: CognitiveDistortionInstance
    let onFeedback: () -> Void

    @State private var showingReframe = false

    /// Get the icon for the distortion type
    private var distortionIcon: String {
        CognitiveDistortionType(rawValue: distortion.distortionType)?.icon ?? "brain.head.profile"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: distortionIcon)
                    .foregroundStyle(.orange)
                Text(distortion.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Description
            Text(distortion.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            // What was detected
            VStack(alignment: .leading, spacing: 4) {
                Text("What I noticed:")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\"\(distortion.quote)\"")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            // Reframe suggestion
            Button {
                withAnimation {
                    showingReframe.toggle()
                }
            } label: {
                HStack {
                    Text(showingReframe ? "Hide alternative perspective" : "See alternative perspective")
                        .font(.caption)
                    Image(systemName: showingReframe ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }

            if showingReframe {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A different way to look at it:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(distortion.alternativePerspective)
                        .font(.caption)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Feedback button
            Button {
                onFeedback()
            } label: {
                Text("Was this helpful?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct DistortionFeedbackSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let analysisId: String
    let distortion: CognitiveDistortionInstance
    let onSubmit: () -> Void

    @State private var selectedAction: DistortionFeedbackAction?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Was this insight helpful?")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Your feedback helps improve the AI's ability to provide supportive insights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 32) {
                    FeedbackButton(
                        emoji: "👍",
                        label: "Helpful",
                        isSelected: selectedAction == .helpful
                    ) {
                        selectedAction = .helpful
                    }

                    FeedbackButton(
                        emoji: "👎",
                        label: "Not Helpful",
                        isSelected: selectedAction == .notHelpful
                    ) {
                        selectedAction = .notHelpful
                    }

                    FeedbackButton(
                        emoji: "🚫",
                        label: "Dismiss",
                        isSelected: selectedAction == .dismiss
                    ) {
                        selectedAction = .dismiss
                    }
                }

                Spacer()

                Button {
                    Task { await submitFeedback() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Submit Feedback")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAction == nil || isSubmitting)
            }
            .padding()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submitFeedback() async {
        guard let action = selectedAction else { return }

        isSubmitting = true

        let service = JournalService(supabase: container.supabase)
        try? await service.submitDistortionFeedback(
            analysisId: analysisId,
            distortionType: distortion.distortionType,
            action: action
        )

        isSubmitting = false
        onSubmit()
    }
}

struct FeedbackButton: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 40))
                Text(label)
                    .font(.caption)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let sampleAnalysis = JournalAnalysis(
        id: "1",
        entryId: "1",
        userId: "1",
        emotionalThemes: ["reflective", "hopeful", "uncertain"],
        suggestedReframes: [
            SuggestedReframe(original: "I must succeed", reframe: "Consider what 'success' means to you personally"),
            SuggestedReframe(original: "I'm not good enough", reframe: "Notice small wins throughout your day"),
            SuggestedReframe(original: "Things never work out", reframe: "Practice self-compassion when things don't go as planned")
        ],
        patternsIdentified: [],
        cognitiveDistortions: [
            CognitiveDistortionInstance(
                distortionType: "all_or_nothing",
                displayName: "All-or-Nothing Thinking",
                quote: "If I don't succeed at this, I'm a complete failure",
                explanation: "This is a common thinking pattern where we see things in black and white.",
                alternativePerspective: "Success exists on a spectrum. Even if things don't go perfectly, you can learn and grow from the experience."
            )
        ],
        supportiveSummary: "Your entry shows a lot of self-awareness. It's natural to feel uncertain during times of change. Remember that acknowledging these feelings is an important step in processing them.",
        aiModel: "grok-2-1106",
        createdAt: Date()
    )

    JournalAnalysisView(analysis: sampleAnalysis)
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
