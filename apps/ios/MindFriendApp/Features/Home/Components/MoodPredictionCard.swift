import SwiftUI

/// Card displaying today's mood prediction with contributing factors
struct MoodPredictionCard: View {
    let prediction: MoodPrediction
    var onTap: (() -> Void)? = nil

    @State private var showDetailSheet = false

    var body: some View {
        Button {
            if let onTap = onTap {
                onTap()
            } else {
                showDetailSheet = true
            }
        } label: {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header row
                HStack {
                    // Mood icon and outlook
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: prediction.moodIcon)
                            .font(.title2)
                            .foregroundColor(SupportTheme.accent)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Today's Outlook")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)

                            Text(prediction.outlookLabel)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundColor(SupportTheme.textPrimary)
                        }
                    }

                    Spacer()

                    // Confidence badge
                    ConfidenceBadge(
                        confidence: prediction.confidencePercent,
                        label: prediction.confidenceLabel
                    )
                }

                // Contributing factors
                if !prediction.factors.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Contributing Factors")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)

                        ForEach(prediction.factors.prefix(3)) { factor in
                            FactorRow(factor: factor)
                        }
                    }
                }

                // Low mood alert
                if prediction.isLowMoodPredicted {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(SupportTheme.accent)

                        Text("Tap for preparation tips")
                            .font(.caption)
                            .foregroundColor(SupportTheme.accent)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(SupportTheme.accent)
                    }
                    .padding(.top, SupportTheme.Spacing.xxs)
                }
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.canvas)
            .cornerRadius(SupportTheme.controlRadius)
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(prediction.isLowMoodPredicted ? "Double tap for preparation tips" : "Double tap for details")
        .sheet(isPresented: $showDetailSheet) {
            PredictionDetailSheet(prediction: prediction)
        }
    }

    private var accessibilityLabel: String {
        var components = [
            "Today's outlook: \(prediction.outlookLabel)",
            "Predicted mood: \(String(format: "%.1f", prediction.predictedMoodValue)) out of 10",
            "\(prediction.confidencePercent) percent confidence",
        ]

        if !prediction.factors.isEmpty {
            let factorDescriptions = prediction.factors.prefix(3).map { $0.description }
            components.append("Contributing factors: \(factorDescriptions.joined(separator: ", "))")
        }

        if prediction.isLowMoodPredicted {
            components.append("Preparation tips available")
        }

        return components.joined(separator: ". ")
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Int
    let label: String

    var color: Color {
        switch confidence {
        case 0..<50: return SupportTheme.textSecondary
        case 50..<75: return SupportTheme.Celebration.gold
        default: return SupportTheme.accent
        }
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Text("\(confidence)%")
                .font(.caption)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(color.opacity(0.1))
        .cornerRadius(SupportTheme.controlRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(confidence) percent confidence, \(label)")
    }
}

// MARK: - Factor Row

struct FactorRow: View {
    let factor: MoodPredictionFactor

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: factor.icon)
                .font(.caption)
                .foregroundColor(SupportTheme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(factor.description)
                .font(.caption)
                .foregroundColor(SupportTheme.textPrimary)
                .lineLimit(2)

            Spacer()

            Text(factor.impactLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(SupportTheme.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(factor.description). Impact: \(factor.impactLabel)")
    }
}

// MARK: - Prediction Detail Sheet

struct PredictionDetailSheet: View {
    let prediction: MoodPrediction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Mood visualization
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: prediction.moodIcon)
                            .font(.system(size: 60))
                            .foregroundColor(SupportTheme.accent)

                        Text(prediction.outlookLabel)
                            .font(.title)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)

                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Text("Predicted mood:")
                            Text(String(format: "%.1f", prediction.predictedMoodValue))
                                .fontWeight(.semibold)
                            Text("/ 10")
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                        .font(.subheadline)

                        ConfidenceBadge(
                            confidence: prediction.confidencePercent,
                            label: "\(prediction.confidenceLabel) confidence"
                        )
                    }
                    .padding(.vertical, SupportTheme.Spacing.l)

                    // All factors
                    if !prediction.factors.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("What's Influencing Your Day")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(prediction.factors) { factor in
                                DetailedFactorRow(factor: factor)
                            }
                        }
                        .supportCard()
                    }

                    // Accuracy info (if available)
                    if let accuracy = prediction.predictionAccuracy {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(SupportTheme.accent)

                            Text("This model has \(Int(Double(truncating: accuracy as NSNumber) * 100))% accuracy")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }

                    // Tips section for low mood days
                    if prediction.isLowMoodPredicted {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Preparation Tips")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            TipRow(
                                icon: "moon.zzz.fill",
                                color: SupportTheme.accent,
                                title: "Prioritize Rest",
                                description: "Give yourself permission to take it easy today"
                            )

                            TipRow(
                                icon: "figure.walk",
                                color: SupportTheme.accent,
                                title: "Gentle Movement",
                                description: "A short walk can boost your mood"
                            )

                            TipRow(
                                icon: "person.2.fill",
                                color: SupportTheme.accent,
                                title: "Reach Out",
                                description: "Connect with someone supportive"
                            )
                        }
                        .supportCard()
                    }
                }
                .padding()
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Today's Prediction")
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
}

// MARK: - Detailed Factor Row

struct DetailedFactorRow: View {
    let factor: MoodPredictionFactor

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            ZStack {
                Circle()
                    .fill(SupportTheme.accent.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: factor.icon)
                    .foregroundColor(SupportTheme.accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(factor.description)
                    .font(.subheadline)

                Text(factor.isPositive ? "Positive influence" : "Challenging factor")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            Spacer()

            Text(factor.impactLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(SupportTheme.accent)
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(factor.description). \(factor.isPositive ? "Positive influence" : "Challenging factor"). Impact: \(factor.impactLabel)"
        )
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SupportTheme.Spacing.l) {
        // Good outlook
        MoodPredictionCard(
            prediction: MoodPrediction(
                id: UUID(),
                userId: UUID(),
                predictedFor: Date(),
                predictedMood: 7.2,
                confidence: 0.78,
                factors: [
                    MoodPredictionFactor(
                        factor: "sleep_hours", impact: 0.8, description: "Good sleep: 7.5h last night"),

                    MoodPredictionFactor(
                        factor: "day_of_week", impact: 0.2, description: "Fridays are usually better for you"),
                ],
                modelVersion: "v1.0",
                featuresUsed: nil as [String: AnyCodableValue]?,
                actualMood: nil as Decimal?,
                predictionAccuracy: nil as Decimal?,
                notificationSent: false,
                notificationSentAt: nil as Date?,
                createdAt: Date()
            )
        )

        // Challenging outlook
        MoodPredictionCard(
            prediction: MoodPrediction(
                id: UUID(),
                userId: UUID(),
                predictedFor: Date(),
                predictedMood: 3.5,
                confidence: 0.65,
                factors: [
                    MoodPredictionFactor(factor: "sleep_hours", impact: -1.2, description: "Only 5h sleep last night"),
                    MoodPredictionFactor(
                        factor: "mood_trend", impact: -0.5, description: "Your mood has been trending down"),
                    MoodPredictionFactor(
                        factor: "day_of_week", impact: -0.3, description: "Mondays tend to be harder for you"),
                ],
                modelVersion: "v1.0",
                featuresUsed: nil as [String: AnyCodableValue]?,
                actualMood: nil as Decimal?,
                predictionAccuracy: nil as Decimal?,
                notificationSent: true,
                notificationSentAt: Date(),
                createdAt: Date()
            )
        )
    }
    .padding()
    .background(SupportTheme.canvas)
}
