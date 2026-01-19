// SOSCheckInView.swift
// MindFriend - Post-Intervention Check-In for SOS

import SwiftUI

/// Post-intervention rating and mood capture
struct SOSCheckInView: View {
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let onComplete: (Int, Int) -> Void

    @State private var helpfulnessRating: Int = 0
    @State private var moodAfter: Int = 3

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("You did great")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Taking a moment to breathe takes courage.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.horizontal, 40)

            // Rating section
            VStack(spacing: 16) {
                Text("Was this helpful?")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            helpfulnessRating = rating
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Image(systemName: rating <= helpfulnessRating ? "star.fill" : "star")
                                .font(.system(size: 32))
                                .foregroundStyle(rating <= helpfulnessRating ? .yellow : .white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(rating) star\(rating == 1 ? "" : "s")")
                        .accessibilityAddTraits(helpfulnessRating == rating ? .isSelected : [])
                    }
                }
            }

            // Mood after
            VStack(spacing: 16) {
                Text("How do you feel now?")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 16) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            moodAfter = mood
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Text(moodEmoji(for: mood))
                                .font(.system(size: 36))
                                .scaleEffect(moodAfter == mood ? 1.2 : 1.0)
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
            VStack(spacing: 8) {
                Text("Remember: You can use the SOS button anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                Text("We're always here. 💙")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            // Complete button
            Button {
                onComplete(helpfulnessRating, moodAfter)
            } label: {
                Text("Back to Home")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .disabled(helpfulnessRating == 0)
            .opacity(helpfulnessRating == 0 ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.3),
                    Color(red: 0.08, green: 0.1, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
