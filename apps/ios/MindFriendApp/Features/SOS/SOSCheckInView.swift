// SOSCheckInView.swift
// MindFriend - Post-Intervention Check-In for SOS

import SwiftUI

/// Post-intervention rating and mood capture
struct SOSCheckInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let onComplete: (Int, Int) -> Void

    @State private var helpfulnessRating: Int = 0
    @State private var moodAfter: Int = 3

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xl) {
            // Header
            VStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        SupportTheme.surface
                    )

                Text("You did great")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("Taking a moment to breathe takes courage.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, SupportTheme.Spacing.xl)

            Divider()
                .background(SupportTheme.textPrimary.opacity(0.2))
                .padding(.horizontal, SupportTheme.Spacing.xl)

            // Rating section
            VStack(spacing: SupportTheme.Spacing.m) {
                Text("Was this helpful?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary)

                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            helpfulnessRating = rating
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Image(systemName: rating <= helpfulnessRating ? "star.fill" : "star")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    rating <= helpfulnessRating
                                        ? SupportTheme.Celebration.gold : SupportTheme.textPrimary.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(rating) star\(rating == 1 ? "" : "s")")
                        .accessibilityAddTraits(helpfulnessRating == rating ? .isSelected : [])
                    }
                }
            }

            // Mood after
            VStack(spacing: SupportTheme.Spacing.m) {
                Text("How do you feel now?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary)

                HStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            moodAfter = mood
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Text(moodEmoji(for: mood))
                                .font(.system(size: 36))
                                .scaleEffect(reduceMotion ? 1 : (moodAfter == mood ? 1.2 : 1.0))
                                .opacity(moodAfter == mood ? 1.0 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(moodLabel(for: mood))
                        .accessibilityAddTraits(moodAfter == mood ? .isSelected : [])
                    }
                }
            }

            Spacer()

            // Encouragement
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Remember: You can use the SOS button anytime.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))

                Text("We're always here. 💙")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, SupportTheme.Spacing.xl)

            // Complete button
            Button {
                onComplete(helpfulnessRating, moodAfter)
            } label: {
                Text("Back to Home")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.m)
                    .background(
                        SupportTheme.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.bottom, SupportTheme.Spacing.xl)
            .disabled(helpfulnessRating == 0)
            .opacity(helpfulnessRating == 0 ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SupportTheme.surface
        )
    }

    private func moodEmoji(for mood: Int) -> String {
        switch mood {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😌"
        default: return "😐"
        }
    }

    private func moodLabel(for mood: Int) -> String {
        switch mood {
        case 1: return "Very upset"
        case 2: return "Somewhat upset"
        case 3: return "Neutral"
        case 4: return "Somewhat calm"
        case 5: return "Calm"
        default: return "Neutral"
        }
    }
}

#Preview {
    SOSCheckInView { rating, mood in
        print("Rating: \(rating), Mood: \(mood)")
    }
    .environmentObject(DependencyContainer.preview)
}
