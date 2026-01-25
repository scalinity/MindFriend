//
//  PathwayCard.swift
//  MindFriendApp
//
//  Created by Claude on 2026-01-25.
//

import SwiftUI

struct ActivePathwayCard: View {
    let userPathway: UserPathway
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // Pathway icon
                    if let iconName = userPathway.pathway?.iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 28))
                            .foregroundColor(colorFromHex(userPathway.pathway?.color ?? "#5C6BC0"))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(colorFromHex(userPathway.pathway?.color ?? "#5C6BC0").opacity(0.1))
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(userPathway.pathway?.name ?? "Pathway")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Day \(userPathway.currentDay) • \(userPathway.currentPhaseName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Progress percentage
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(userPathway.progressPercentage * 100))%")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Complete")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorFromHex(userPathway.pathway?.color ?? "#5C6BC0"))
                            .frame(width: geometry.size.width * userPathway.progressPercentage, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(
            "\(userPathway.pathway?.name ?? "Pathway"). Day \(userPathway.currentDay), \(userPathway.currentPhaseName). \(Int(userPathway.progressPercentage * 100)) percent complete."
        )
        .accessibilityHint("Double tap to view pathway details")
    }

    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double((rgb & 0x0000FF)) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}

#Preview {
    VStack(spacing: 16) {
        ActivePathwayCard(
            userPathway: UserPathway(
                id: UUID(),
                userId: UUID(),
                pathwayId: UUID(),
                startedAt: Date(),
                currentPhase: 2,
                currentDay: 15,
                currentPhaseDay: 8,
                status: .active,
                pausedAt: nil,
                completedAt: nil,
                personalization: PathwayPersonalization(),
                createdAt: Date(),
                updatedAt: Date(),
                pathway: TransitionPathway(
                    id: UUID(),
                    key: "job_loss",
                    name: "Career Transition",
                    description: "Navigate job loss or career change",
                    category: .career,
                    durationWeeks: 8,
                    phases: [],
                    isPremium: true,
                    iconName: "briefcase.fill",
                    color: "#5C6BC0",
                    crisisResources: nil,
                    createdAt: Date()
                ),
                progress: nil
            ),
            onTap: {}
        )
        .padding()

        ActivePathwayCard(
            userPathway: UserPathway(
                id: UUID(),
                userId: UUID(),
                pathwayId: UUID(),
                startedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60),
                currentPhase: 3,
                currentDay: 45,
                currentPhaseDay: 10,
                status: .active,
                pausedAt: nil,
                completedAt: nil,
                personalization: PathwayPersonalization(),
                createdAt: Date(),
                updatedAt: Date(),
                pathway: TransitionPathway(
                    id: UUID(),
                    key: "grief",
                    name: "Grief Journey",
                    description: "Compassionate support through loss",
                    category: .loss,
                    durationWeeks: 12,
                    phases: [],
                    isPremium: true,
                    iconName: "leaf.fill",
                    color: "#78909C",
                    crisisResources: nil,
                    createdAt: Date()
                ),
                progress: nil
            ),
            onTap: {}
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
