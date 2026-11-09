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
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
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
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(SupportTheme.accent)
                Text("Your Insights")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("Here's what I noticed in your journal entry. Remember, these are gentle observations to help you reflect, not judgments.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    private var emotionalThemesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Emotional Themes", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(SupportTheme.accent)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
                ForEach(analysis.emotionalThemes, id: \.self) { theme in
                    Text(theme.capitalized)
                        .font(.subheadline)
                        .padding(.horizontal, SupportTheme.Spacing.s)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.surface)
                        .foregroundStyle(SupportTheme.accent)
                        .clipShape(Capsule())
                }
            }
        }
        .supportCard()
    }

    private var supportiveInsightSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("A Gentle Reflection", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(SupportTheme.accent)

            Text(analysis.supportiveSummary)
                .font(.body)
                .lineSpacing(4)
        }
        .supportCard()
    }

    private var cognitiveDistortionsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Label("Thinking Patterns", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.accent)

                Text("These are common patterns many people experience. Recognizing them is the first step to a more balanced perspective.")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            ForEach(analysis.cognitiveDistortions) { distortion in
                DistortionCard(distortion: distortion) {
                    showingFeedbackFor = distortion
                }
            }
        }
        .supportCard()
    }

    private var suggestedReframesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Things to Consider", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(SupportTheme.accent)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                ForEach(analysis.suggestedReframes) { reframe in
                    HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "circle.fill")
                            .font(.system(.caption2))
                            .foregroundStyle(SupportTheme.textSecondary)
                            .padding(.top, SupportTheme.Spacing.xxs)
                        Text(reframe.reframe)
                            .font(.subheadline)
                    }
                }
            }
        }
        .supportCard()
    }

    private var sentimentSection: some View {
        HStack {
            Text("Overall Tone:")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
            Text(analysis.overallSentiment.capitalized)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(sentimentColor)
        }
    }

    private var sentimentColor: Color {
        switch analysis.overallSentiment.lowercased() {
        case "positive", "hopeful", "grateful":
            return SupportTheme.accent
        case "negative", "sad", "frustrated", "anxious":
            return SupportTheme.accent
        case "neutral", "reflective":
            return SupportTheme.accent
        default:
            return .secondary
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("About these insights")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SupportTheme.textSecondary)

            Text("This AI analysis is designed to support your self-reflection journey. It's not a substitute for professional mental health support. If you're struggling, please reach out to a counselor or therapist.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }
}

// MARK: - Supporting Views

struct DistortionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let distortion: CognitiveDistortionInstance
    let onFeedback: () -> Void

    @State private var showingReframe = false

    /// Get the icon for the distortion type
    private var distortionIcon: String {
        CognitiveDistortionType(rawValue: distortion.distortionType)?.icon ?? "brain.head.profile"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                Image(systemName: distortionIcon)
                    .foregroundStyle(SupportTheme.accent)
                Text(distortion.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Description
            Text(distortion.explanation)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            // What was detected
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text("What I noticed:")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\"\(distortion.quote)\"")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Reframe suggestion
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingReframe.toggle()
                }
            } label: {
                HStack {
                    Text(showingReframe ? "Hide alternative perspective" : "See alternative perspective")
                        .font(.caption)
                    Image(systemName: showingReframe ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(SupportTheme.accent)
            }

            if showingReframe {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("A different way to look at it:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(distortion.alternativePerspective)
                        .font(.caption)
                        .padding(SupportTheme.Spacing.xs)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            // Feedback button
            Button {
                onFeedback()
            } label: {
                Text("Was this helpful?")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 2, y: 1)
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
            VStack(spacing: SupportTheme.Spacing.l) {
                Text("Was this insight helpful?")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Your feedback helps improve the AI's ability to provide supportive insights.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: SupportTheme.Spacing.xl) {
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
                .buttonStyle(.supportPrimary)
                .disabled(selectedAction == nil || isSubmitting)
            }
            .padding(SupportTheme.Spacing.m)
            .supportScreen()
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
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text(emoji)
                    .font(.system(.largeTitle))
                Text(label)
                    .font(.caption)
            }
            .padding(SupportTheme.Spacing.m)
            .background(isSelected ? SupportTheme.accent.opacity(0.1) : SupportTheme.separator)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .stroke(isSelected ? SupportTheme.accent : .clear, lineWidth: 2)
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
