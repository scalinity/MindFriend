import SwiftUI

// MARK: - Emotion Detail Sheet

/// Sheet showing detailed emotion analysis and history
/// Presented when user taps the emotion badge
struct EmotionDetailSheet: View {

    // MARK: - Properties

    /// Current emotion result (optional, nil if no current emotion)
    let currentEmotion: EmotionResult?

    /// History of emotions detected during this session
    let emotionHistory: [EmotionSnapshot]

    /// Binding to control sheet presentation
    @Binding var isPresented: Bool

    /// Callback when user disables emotion analysis
    let onDisableEmotions: () -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Current emotion card
                    if let emotion = currentEmotion {
                        currentEmotionCard(emotion)
                    } else {
                        noEmotionCard
                    }

                    // Emotion breakdown chart
                    if let emotion = currentEmotion {
                        emotionBreakdownSection(emotion.allProbabilities)
                    }

                    // Emotion timeline
                    if !emotionHistory.isEmpty {
                        emotionTimelineSection
                    }

                    // Context note
                    Text("Based on voice analysis using on-device AI emotion detection. Your voice data is never stored or shared.")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Settings link
                    Button {
                        // Navigate to voice settings
                        dismiss()
                        onDisableEmotions()
                    } label: {
                        Label("Emotion Settings", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                    }
                    .padding(.bottom, SupportTheme.Spacing.m)
                }
                .padding()
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportSheet()
            .navigationTitle("Your Emotional State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Current Emotion Card

    @ViewBuilder
    private func currentEmotionCard(_ emotion: EmotionResult) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Emoji - use shared helper
            Text(EmotionSnapshot.emoji(for: emotion.emotion))
                .font(.system(size: 64))

            // Emotion name
            Text(emotion.emotion.capitalized)
                .font(.title.weight(.semibold))

            // Confidence
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption)
                Text("\(Int(emotion.confidence * 100))% confidence")
                    .font(.subheadline)
            }
            .foregroundStyle(SupportTheme.textSecondary)

            // Confidence level description
            Text(confidenceDescription(emotion.confidence))
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.vertical, SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.cardRadius)
    }

    private var noEmotionCard: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No emotion detected yet")
                .font(.headline)

            Text("Speak for at least 3 seconds to analyze your emotional state")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.cardRadius)
    }

    // MARK: - Emotion Breakdown

    @ViewBuilder
    private func emotionBreakdownSection(_ probabilities: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Emotion Breakdown")
                .font(.headline)

            let sortedEmotions = probabilities.sorted { $0.value > $1.value }

            ForEach(sortedEmotions, id: \.key) { emotion, probability in
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Use shared emoji helper
                    Text(EmotionSnapshot.emoji(for: emotion))
                        .font(.title3)

                    Text(emotion.capitalized)
                        .font(.subheadline)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.surface)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                // Use shared color helper
                                .fill(SupportTheme.accent)
                                .frame(width: geometry.size.width * probability, height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(probability * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SupportTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .supportCard()
    }

    // MARK: - Emotion Timeline

    private var emotionTimelineSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Session Timeline")
                .font(.headline)

            ForEach(emotionHistory.suffix(10).reversed()) { snapshot in
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Use instance property which calls shared helper
                    Text(snapshot.emoji)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(snapshot.emotion.capitalized)
                            .font(.subheadline.weight(.medium))

                        Text("\(Int(snapshot.confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Text(snapshot.formattedTimestamp())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.vertical, SupportTheme.Spacing.xs)

                if snapshot.id != emotionHistory.last?.id {
                    Divider()
                }
            }
        }
        .supportCard()
    }

    // MARK: - Helpers

    private func confidenceDescription(_ confidence: Double) -> String {
        if confidence >= 0.8 {
            return "High confidence - clear emotional signal"
        } else if confidence >= 0.6 {
            return "Medium confidence - detectable emotion"
        } else {
            return "Low confidence - subtle emotional cues"
        }
    }
}

// MARK: - Preview

#Preview("With Emotion") {
    EmotionDetailSheet(
        currentEmotion: EmotionResult(
            emotion: "happy",
            confidence: 0.82,
            allProbabilities: [
                "happy": 0.82,
                "calm": 0.10,
                "neutral": 0.05,
                "surprised": 0.02,
                "sad": 0.01,
                "angry": 0.0,
                "fearful": 0.0,
                "disgust": 0.0
            ]
        ),
        emotionHistory: [
            EmotionSnapshot(emotion: "neutral", confidence: 0.65, timestamp: 0),
            EmotionSnapshot(emotion: "happy", confidence: 0.72, timestamp: 30),
            EmotionSnapshot(emotion: "happy", confidence: 0.82, timestamp: 65)
        ],
        isPresented: .constant(true),
        onDisableEmotions: {}
    )
}

#Preview("No Emotion") {
    EmotionDetailSheet(
        currentEmotion: nil,
        emotionHistory: [],
        isPresented: .constant(true),
        onDisableEmotions: {}
    )
}
