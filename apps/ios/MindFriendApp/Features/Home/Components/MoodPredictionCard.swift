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
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    // Mood icon and outlook
                    HStack(spacing: 8) {
                        Image(systemName: prediction.moodIcon)
                            .font(.title2)
                            .foregroundColor(prediction.moodColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today's Outlook")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(prediction.outlookLabel)
                                .font(.headline)
                                .foregroundColor(.primary)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contributing Factors")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(prediction.factors.prefix(3)) { factor in
                            FactorRow(factor: factor)
                        }
                    }
                }

                // Low mood alert
                if prediction.isLowMoodPredicted {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.blue)

                        Text("Tap for preparation tips")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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
            "\(prediction.confidencePercent) percent confidence"
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
        case 0..<50: return .gray
        case 50..<75: return .yellow
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(confidence)%")
                .font(.caption)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(confidence) percent confidence, \(label)")
    }
}

// MARK: - Factor Row

struct FactorRow: View {
    let factor: MoodPredictionFactor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: factor.icon)
                .font(.caption)
                .foregroundColor(factor.impactColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(factor.description)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            Text(factor.impactLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(factor.impactColor)
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
                VStack(spacing: 24) {
                    // Mood visualization
                    VStack(spacing: 8) {
                        Image(systemName: prediction.moodIcon)
                            .font(.system(size: 60))
                            .foregroundColor(prediction.moodColor)

                        Text(prediction.outlookLabel)
                            .font(.title)
                            .fontWeight(.bold)

                        HStack(spacing: 4) {
                            Text("Predicted mood:")
                            Text(String(format: "%.1f", prediction.predictedMoodValue))
                                .fontWeight(.semibold)
                            Text("/ 10")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)

                        ConfidenceBadge(
                            confidence: prediction.confidencePercent,
                            label: "\(prediction.confidenceLabel) confidence"
                        )
                    }
                    .padding(.vertical, 24)

                    // All factors
                    if !prediction.factors.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What's Influencing Your Day")
                                .font(.headline)

                            ForEach(prediction.factors) { factor in
                                DetailedFactorRow(factor: factor)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // Accuracy info (if available)
                    if let accuracy = prediction.predictionAccuracy {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.green)

                            Text("This model has \(Int(Double(truncating: accuracy as NSNumber) * 100))% accuracy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Tips section for low mood days
                    if prediction.isLowMoodPredicted {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preparation Tips")
                                .font(.headline)

                            TipRow(
                                icon: "moon.zzz.fill",
                                color: .purple,
                                title: "Prioritize Rest",
                                description: "Give yourself permission to take it easy today"
                            )

                            TipRow(
                                icon: "figure.walk",
                                color: .green,
                                title: "Gentle Movement",
                                description: "A short walk can boost your mood"
                            )

                            TipRow(
                                icon: "person.2.fill",
                                color: .blue,
                                title: "Reach Out",
                                description: "Connect with someone supportive"
                            )
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(factor.impactColor.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: factor.icon)
                    .foregroundColor(factor.impactColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(factor.description)
                    .font(.subheadline)

                Text(factor.isPositive ? "Positive influence" : "Challenging factor")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(factor.impactLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(factor.impactColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(factor.description). \(factor.isPositive ? "Positive influence" : "Challenging factor"). Impact: \(factor.impactLabel)")
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Good outlook
        MoodPredictionCard(
            prediction: MoodPrediction(
                id: UUID(),
                userId: UUID(),
                predictedFor: Date(),
                predictedMood: 7.2,
                confidence: 0.78,
                factors: [
                    MoodPredictionFactor(factor: "sleep_hours", impact: 0.8, description: "Good sleep: 7.5h last night"),
                    MoodPredictionFactor(factor: "streak", impact: 0.3, description: "5-day streak is providing stability"),
                    MoodPredictionFactor(factor: "day_of_week", impact: 0.2, description: "Fridays are usually better for you")
                ],
                modelVersion: "v1.0",
                featuresUsed: nil,
                actualMood: nil,
                predictionAccuracy: nil,
                notificationSent: false,
                notificationSentAt: nil,
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
                    MoodPredictionFactor(factor: "mood_trend", impact: -0.5, description: "Your mood has been trending down"),
                    MoodPredictionFactor(factor: "day_of_week", impact: -0.3, description: "Mondays tend to be harder for you")
                ],
                modelVersion: "v1.0",
                featuresUsed: nil,
                actualMood: nil,
                predictionAccuracy: nil,
                notificationSent: true,
                notificationSentAt: Date(),
                createdAt: Date()
            )
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
