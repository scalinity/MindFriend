import SwiftUI

/// View displayed when a preemptive intervention is suggested for a low mood prediction
struct PreemptiveInterventionView: View {
    let intervention: PreemptiveIntervention
    let prediction: MoodPrediction?
    let onAccept: () -> Void
    let onDismiss: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFeedbackSheet = false
    @State private var feedbackText = ""

    private var headerAccessibilityLabel: String {
        var label = intervention.interventionType.title
        if let prediction = prediction {
            label += ". Today's outlook: \(prediction.outlookLabel)"
        }
        return label
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        showFeedbackSheet = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close and provide feedback")
                }
                .padding(.horizontal)

                // Icon and title
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(intervention.interventionType.color.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: intervention.interventionType.icon)
                            .font(.system(size: 36))
                            .foregroundColor(intervention.interventionType.color)
                    }
                    .accessibilityHidden(true)

                    Text(intervention.interventionType.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let prediction = prediction {
                        Text("Today's outlook: \(prediction.outlookLabel)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headerAccessibilityLabel)
            }
            .padding(.top, 24)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Main message
                    Text(intervention.content)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()

                    // Contributing factors (if prediction available)
                    if let prediction = prediction, !prediction.factors.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What We Noticed")
                                .font(.headline)

                            ForEach(prediction.factors.prefix(3)) { factor in
                                InterventionFactorRow(factor: factor)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // Suggested exercise card
                    if intervention.suggestedExerciseId != nil {
                        SuggestedExerciseCard(
                            interventionType: intervention.interventionType,
                            onStart: {
                                onAccept()
                                dismiss()
                            }
                        )
                    }

                    // Alternative actions
                    VStack(spacing: 12) {
                        Text("Or try these:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            AlternativeActionButton(
                                icon: "message.fill",
                                title: "Chat",
                                color: .blue
                            ) {
                                onAccept()
                                dismiss()
                            }

                            AlternativeActionButton(
                                icon: "book.fill",
                                title: "Journal",
                                color: .purple
                            ) {
                                onAccept()
                                dismiss()
                            }

                            AlternativeActionButton(
                                icon: "person.2.fill",
                                title: "Circle",
                                color: .green
                            ) {
                                onAccept()
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
                .padding()
            }

            // Primary CTA
            Button {
                onAccept()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                    Text("Start Recommended Exercise")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(intervention.interventionType.color)
                .cornerRadius(16)
            }
            .accessibilityLabel("Start recommended exercise")
            .accessibilityHint("Begins the suggested wellness exercise")
            .padding()
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showFeedbackSheet) {
            DismissFeedbackSheet(
                feedbackText: $feedbackText,
                onDismiss: { feedback in
                    onDismiss(feedback)
                    dismiss()
                }
            )
        }
    }
}

// MARK: - Intervention Factor Row

struct InterventionFactorRow: View {
    let factor: MoodPredictionFactor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: factor.icon)
                .foregroundColor(factor.impactColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(factor.description)
                .font(.subheadline)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(factor.description)
    }
}

// MARK: - Suggested Exercise Card

struct SuggestedExerciseCard: View {
    let interventionType: PreemptiveInterventionType
    let onStart: () -> Void

    var exerciseTitle: String {
        switch interventionType {
        case .restSuggestion: return "Calming Breath"
        case .movementSuggestion: return "Gentle Stretch"
        case .patternBreak: return "Grounding Exercise"
        case .generalSupport: return "Quick Check-in"
        }
    }

    var exerciseDuration: String {
        switch interventionType {
        case .restSuggestion: return "5 min"
        case .movementSuggestion: return "7 min"
        case .patternBreak: return "3 min"
        case .generalSupport: return "5 min"
        }
    }

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(interventionType.color.opacity(0.1))
                        .frame(width: 60, height: 60)

                    Image(systemName: interventionType.icon)
                        .font(.title2)
                        .foregroundColor(interventionType.color)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended for You")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(exerciseTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(exerciseDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(interventionType.color)
                    .accessibilityHidden(true)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recommended for you: \(exerciseTitle), \(exerciseDuration)")
        .accessibilityHint("Double tap to start exercise")
    }
}

// MARK: - Alternative Action Button

struct AlternativeActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .foregroundColor(color)
                }
                .accessibilityHidden(true)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to open \(title)")
    }
}

// MARK: - Dismiss Feedback Sheet

struct DismissFeedbackSheet: View {
    @Binding var feedbackText: String
    let onDismiss: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Was this helpful?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your feedback helps us improve predictions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Quick feedback buttons
                HStack(spacing: 20) {
                    InterventionFeedbackButton(
                        emoji: "helpful",
                        label: "Helpful",
                        color: .green
                    ) {
                        onDismiss("helpful")
                    }

                    InterventionFeedbackButton(
                        emoji: "not_now",
                        label: "Not Now",
                        color: .yellow
                    ) {
                        onDismiss("not_now")
                    }

                    InterventionFeedbackButton(
                        emoji: "not_helpful",
                        label: "Not Helpful",
                        color: .red
                    ) {
                        onDismiss("not_helpful")
                    }
                }

                Divider()

                // Optional text feedback
                VStack(alignment: .leading, spacing: 8) {
                    Text("Any other feedback? (optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Tell us more...", text: $feedbackText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }

                Spacer()

                Button {
                    onDismiss(feedbackText.isEmpty ? "dismissed" : feedbackText)
                } label: {
                    Text("Skip for Now")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Feedback Button

struct InterventionFeedbackButton: View {
    let emoji: String
    let label: String
    let color: Color
    let action: () -> Void

    var icon: String {
        switch emoji {
        case "helpful": return "hand.thumbsup.fill"
        case "not_now": return "clock.fill"
        case "not_helpful": return "hand.thumbsdown.fill"
        default: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                }
                .accessibilityHidden(true)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityHint("Submit \(label.lowercased()) as feedback")
    }
}

// MARK: - Preview

#Preview {
    PreemptiveInterventionView(
        intervention: PreemptiveIntervention(
            id: UUID(),
            userId: UUID(),
            predictionId: UUID(),
            interventionType: .restSuggestion,
            content: "Based on your sleep patterns, today might be challenging. A calming exercise could help you feel more grounded.",
            suggestedExerciseId: UUID(),
            status: .delivered,
            deliveredAt: Date(),
            userResponse: nil,
            responseRecordedAt: nil,
            createdAt: Date()
        ),
        prediction: MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 3.2,
            confidence: 0.72,
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
        ),
        onAccept: { print("Accepted") },
        onDismiss: { feedback in print("Dismissed: \(feedback)") }
    )
}
