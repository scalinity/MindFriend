//
//  ExerciseRecommendStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain personalized recommendations
//

import SwiftUI

/// Step 2: Show how recommendations adapt to your state
struct ExerciseRecommendStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var capacityLevel = 1
    @State private var showExplanation = false

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: .purple,
            headline: "Personalized For You",
            subheadline: "We recommend exercises based on your current energy and mood.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Capacity indicator
                VStack(spacing: 8) {
                    Text("Your Current Capacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(level <= capacityLevel ? capacityColor : Color(.systemGray5))
                                .frame(width: 36, height: 8)
                        }
                    }

                    Text(capacityLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(capacityColor)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works:")
                        .font(.subheadline.weight(.medium))

                    VStack(alignment: .leading, spacing: 6) {
                        InfoPoint(text: "Low capacity? Quick, simple exercises")
                        InfoPoint(text: "Feeling good? Try longer, deeper practices")
                        InfoPoint(text: "Updates based on your mood check-ins")
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .opacity(showExplanation ? 1 : 0)
            }
            .onAppear {
                animateCapacity()
            }
        }
    }

    private var capacityColor: Color {
        switch capacityLevel {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        default: return .gray
        }
    }

    private var capacityLabel: String {
        switch capacityLevel {
        case 1: return "Very Low"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "Good"
        case 5: return "High"
        default: return "Unknown"
        }
    }

    private func animateCapacity() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                capacityLevel += 1
            }
            if capacityLevel >= 4 {
                timer.invalidate()
                withAnimation(.easeOut(duration: 0.3)) {
                    showExplanation = true
                }
            }
        }
    }
}

private struct InfoPoint: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ExerciseRecommendStep(onNext: {}, onSkip: {})
}
