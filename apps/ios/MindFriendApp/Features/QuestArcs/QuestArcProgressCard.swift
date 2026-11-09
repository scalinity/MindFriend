//
//  QuestArcProgressCard.swift
//  MindFriendApp
//
//  Home screen card showing active quest arc progress
//

import SwiftUI

struct QuestArcProgressCard: View {
    let userArc: UserQuestArc
    let onTap: () -> Void

    private var arc: QuestArc? {
        userArc.arc
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(SupportTheme.accent)
                            Text("Active Journey")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Text(arc?.title ?? "Quest Journey")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(SupportTheme.textPrimary)
                    }

                    Spacer()

                    // Category icon
                    if let category = arc?.category {
                        categoryIcon(for: category)
                    }
                }

                // Progress bar with milestones
                progressSection

                // Stats row
                HStack {
                    statItem(
                        value: "\(userArc.currentDay)",
                        label: "Day",
                        icon: "calendar"
                    )

                    Divider()
                        .frame(height: 24)

                    statItem(
                        value: "\(userArc.completedMilestones.count)",
                        label: "Milestones",
                        icon: "flag.fill"
                    )

                    Divider()
                        .frame(height: 24)

                    statItem(
                        value: "\(Int(userArc.progressPercentage * 100))%",
                        label: "Complete",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
                .padding(.top, SupportTheme.Spacing.xxs)

                // Status badge for paused arcs
                if userArc.status == .paused {
                    pausedBadge
                }
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress Section

    // Cache milestone marker data to prevent recalculation on every layout pass
    private struct MilestoneMarker: Identifiable {
        let id: Int
        let position: CGFloat
        let isCompleted: Bool
    }

    private func milestoneMarkers(width: CGFloat) -> [MilestoneMarker] {
        guard userArc.snapshotDurationDays > 0 else { return [] }
        return userArc.snapshotMilestoneDays.map { day in
            MilestoneMarker(
                id: day,
                position: CGFloat(day) / CGFloat(userArc.snapshotDurationDays),
                isCompleted: userArc.currentDay >= day
            )
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            // Day progress text
            HStack {
                Text("Day \(userArc.currentDay) of \(userArc.snapshotDurationDays)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()

                if let nextMilestone = userArc.nextMilestoneDay {
                    Text("Next milestone: Day \(nextMilestone)")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            // Progress bar with milestone markers (optimized rendering)
            GeometryReader { geometry in
                let width = geometry.size.width
                let categoryColor = QuestArcCategory.color(for: arc?.category ?? "")
                let markers = milestoneMarkers(width: width)

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.separator)
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(
                            SupportTheme.surface
                        )
                        .frame(width: width * userArc.progressPercentage, height: 8)

                    // Milestone markers (using cached positions)
                    ForEach(markers) { marker in
                        Circle()
                            .fill(marker.isCompleted ? categoryColor : SupportTheme.separator)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(SupportTheme.canvas, lineWidth: 2)
                            )
                            .offset(x: (width * marker.position) - 6)
                    }
                }
            }
            .frame(height: 12)
        }
    }

    // MARK: - Supporting Views

    private func categoryIcon(for category: String) -> some View {
        Image(systemName: QuestArcCategory.iconName(for: category))
            .font(.title2)
            .foregroundStyle(QuestArcCategory.color(for: category))
            .frame(width: 44, height: 44)
            .background(QuestArcCategory.color(for: category).opacity(0.15))
            .clipShape(Circle())
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pausedBadge: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: "pause.circle.fill")
            Text("Paused")
                .font(.caption.weight(.medium))
            Text("- Tap to resume")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .foregroundStyle(SupportTheme.accent)
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    // MARK: - Helpers

}

// MARK: - No Active Arc Card

struct NoActiveArcCard: View {
    let onBrowse: () -> Void

    var body: some View {
        Button(action: onBrowse) {
            VStack(spacing: SupportTheme.Spacing.m) {
                Image(systemName: "map.fill")
                    .font(.largeTitle)
                    .foregroundStyle(SupportTheme.textSecondary)

                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Start a Quest Journey")
                        .font(.headline)

                    Text("Multi-day programs to build lasting habits")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Browse Journeys")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(SupportTheme.accent)
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity)
            .background(SupportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview("Active Arc") {
    QuestArcProgressCard(
        userArc: UserQuestArc(
            id: UUID(),
            userId: UUID(),
            arcId: UUID(),
            currentDay: 5,
            status: .active,
            startedAt: Date(),
            pausedAt: nil,
            completedAt: nil,
            abandonedAt: nil,
            lastQuestCompletedAt: nil,
            snapshotDurationDays: 14,
            snapshotMilestoneDays: [3, 7, 14],
            arc: QuestArc(
                id: UUID(),
                title: "Stress Relief Journey",
                description: "A 14-day program",
                category: "stress",
                durationDays: 14,
                difficultyLevel: "beginner",
                isPremium: false,
                milestoneDays: [3, 7, 14],
                iconName: "brain.head.profile",
                stepCount: 5,
                userEnrolled: true,
                userCompleted: false,
                userProgress: 5
            )
        ),
        onTap: {}
    )
    .padding(SupportTheme.Spacing.m)
}

#Preview("No Active Arc") {
    NoActiveArcCard(onBrowse: {})
        .padding(SupportTheme.Spacing.m)
}
