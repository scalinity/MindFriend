import SwiftUI

// MARK: - Emotion Detail Sheet

/// Sheet showing detailed emotion analysis and history
/// Presented when user taps the emotion badge
struct EmotionDetailSheet: View {

    // MARK: - Properties

    /// Current emotion result (optional, nil if no current emotion)
    let currentEmotion: EmotionAnalyzer.EmotionResult?

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
                VStack(spacing: 24) {
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
                        .foregroundStyle(.secondary)
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
                    .padding(.bottom, 16)
                }
                .padding()
            }
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
    private func currentEmotionCard(_ emotion: EmotionAnalyzer.EmotionResult) -> some View {
        VStack(spacing: 16) {
            // Emoji - use shared helper
            Text(EmotionSnapshot.emoji(for: emotion.emotion))
                .font(.system(size: 64))

            // Emotion name
            Text(emotion.emotion.capitalized)
                .font(.title.weight(.semibold))

            // Confidence
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption)
                Text("\(Int(emotion.confidence * 100))% confidence")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)

            // Confidence level description
            Text(confidenceDescription(emotion.confidence))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    private var noEmotionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No emotion detected yet")
                .font(.headline)

            Text("Speak for at least 3 seconds to analyze your emotional state")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Emotion Breakdown

    @ViewBuilder
    private func emotionBreakdownSection(_ probabilities: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emotion Breakdown")
                .font(.headline)

            let sortedEmotions = probabilities.sorted { $0.value > $1.value }

            ForEach(sortedEmotions, id: \.key) { emotion, probability in
                HStack(spacing: 12) {
                    // Use shared emoji helper
                    Text(EmotionSnapshot.emoji(for: emotion))
                        .font(.title3)

                    Text(emotion.capitalized)
                        .font(.subheadline)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                // Use shared color helper
                                .fill(EmotionSnapshot.color(for: emotion).opacity(0.8))
                                .frame(width: geometry.size.width * probability, height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(probability * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Emotion Timeline

    private var emotionTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Timeline")
                .font(.headline)

            ForEach(emotionHistory.suffix(10).reversed()) { snapshot in
                HStack(spacing: 12) {
                    // Use instance property which calls shared helper
                    Text(snapshot.emoji)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.emotion.capitalized)
                            .font(.subheadline.weight(.medium))

                        Text("\(Int(snapshot.confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(snapshot.formattedTimestamp())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)

                if snapshot.id != emotionHistory.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        currentEmotion: EmotionAnalyzer.EmotionResult(
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
