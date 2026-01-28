//
//  CirclesRitualsStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Group rituals and activities
//

import SwiftUI

/// Step 3: Show group rituals and support features
struct CirclesRitualsStep: View {
    let onComplete: () -> Void

    @State private var showRituals = false

    private let rituals: [(icon: String, color: Color, name: String, description: String)] = [
        ("sunrise.fill", .orange, "Morning Intentions", "Start the day together with shared goals"),
        ("moon.stars.fill", .purple, "Evening Reflection", "Wind down and share gratitude"),
        ("figure.mind.and.body", .green, "Group Exercise", "Do wellness exercises together")
    ]

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: .purple,
            headline: "Rituals & Support",
            subheadline: "Join scheduled group activities and support each other's growth.",
            primaryLabel: "Explore Circles",
            primaryAction: onComplete
        ) {
            VStack(spacing: 12) {
                ForEach(Array(rituals.enumerated()), id: \.element.name) { index, ritual in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(ritual.color.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: ritual.icon)
                                .foregroundStyle(ritual.color)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ritual.name)
                                .font(.subheadline.weight(.medium))
                            Text(ritual.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showRituals ? 1 : 0)
                    .offset(x: showRituals ? 0 : 20)
                    .animation(
                        .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.15),
                        value: showRituals
                    )
                }

                // Invite prompt
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(.pink)
                    Text("Invite friends to create your first circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.pink.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
                .opacity(showRituals ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .onAppear { showRituals = true }
        }
    }
}

#Preview {
    CirclesRitualsStep(onComplete: {})
}
