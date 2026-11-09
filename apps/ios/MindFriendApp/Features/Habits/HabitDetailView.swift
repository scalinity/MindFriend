import SwiftUI
import UIKit

// MARK: - Habit Detail View

/// Detailed view for a single habit with stats and settings
struct HabitDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let habit: Habit
    @State var streakInfo: HabitStreakInfo

    @State private var weeklyStats: [Int] = Array(repeating: 0, count: 7)
    @State private var isLoading = true
    @State private var isCompleting = false
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false

    private var categoryEmoji: String {
        switch habit.category {
        case .breathing: return "🫁"
        case .meditation: return "🧘"
        case .journaling: return "📝"
        case .movement: return "🏃"
        case .custom: return "✨"
        }
    }

    private var categoryColor: Color {
        switch habit.category {
        case .breathing: return SupportTheme.accent
        case .meditation: return SupportTheme.accent
        case .journaling: return SupportTheme.accent
        case .movement: return SupportTheme.accent
        case .custom: return SupportTheme.accent
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text(categoryEmoji)
                        .font(.system(size: 60))

                    Text(habit.name)
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    Text(habit.fullHabitStatement)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    // Category and difficulty badges
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        HabitBadge(text: habit.category.displayName, color: categoryColor)
                        HabitBadge(text: habit.difficulty.displayName, color: SupportTheme.textSecondary)
                    }
                }
                .padding()

                // Stats section
                VStack(spacing: SupportTheme.Spacing.m) {
                    // Completion rate
                    let completionRate = weeklyStats.filter { $0 == 1 }.count
                    HStack(spacing: SupportTheme.Spacing.l) {
                        HabitStatCard(
                            title: "This Week",
                            value: "\(completionRate)/7",
                            icon: "calendar",
                            color: SupportTheme.accent
                        )

                        HabitStatCard(
                            title: "Duration",
                            value: "\(habit.durationSeconds / 60)m",
                            icon: "clock.fill",
                            color: SupportTheme.accent
                        )
                    }
                }
                .padding(.horizontal)

                // Weekly completion grid
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("This Week")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    WeeklyCompletionGrid(stats: weeklyStats)
                }
                .supportCard()
                .padding(.horizontal)

                // Complete button
                if !streakInfo.isCompletedToday {
                    Button {
                        Task { await completeHabit() }
                    } label: {
                        HStack {
                            if isCompleting {
                                ProgressView()
                                    .tint(SupportTheme.textPrimary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Mark Complete")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(categoryColor)
                        .foregroundStyle(SupportTheme.onAccent)
                        .cornerRadius(SupportTheme.controlRadius)
                    }
                    .disabled(isCompleting)
                    .padding(.horizontal)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SupportTheme.accent)
                        Text("Completed today!")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)
                    .padding(.horizontal)
                }

                // Settings section
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "bell.fill",
                        title: "Reminder",
                        value: habit.reminderTime != nil ? formatTime(habit.reminderTime!) : "Off"
                    )

                    Divider().padding(.leading, SupportTheme.minimumTarget)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        SettingsRow(
                            icon: "trash.fill",
                            title: "Delete Habit",
                            value: nil,
                            isDestructive: true
                        )
                    }
                }
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)
                .padding(.horizontal)

                Spacer(minLength: SupportTheme.Spacing.xl)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Habit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadData()
        }
        .confirmationDialog(
            "Delete Habit?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteHabit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the habit and all its history. This action cannot be undone.")
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            weeklyStats = try await container.habitService.getWeeklyStats(for: habit)
            streakInfo = try await container.habitService.getCurrentStreak(for: habit)
        } catch {
            // Use defaults
        }
    }

    private func completeHabit() async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            try await container.habitService.completeHabit(habit)
            streakInfo = try await container.habitService.getCurrentStreak(for: habit)
            weeklyStats = try await container.habitService.getWeeklyStats(for: habit)

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Check for milestone
            if streakInfo.currentStreak > 0 && streakInfo.currentStreak % 7 == 0 {
                try? await container.habitNotificationService.scheduleStreakMilestoneNotification(
                    habit: habit,
                    streak: streakInfo.currentStreak,
                    milestone: streakInfo.currentStreak
                )
            }
        } catch {
            // Handle error
        }
    }

    private func deleteHabit() async {
        do {
            // Cancel notifications
            container.habitNotificationService.cancelAllNotifications(for: habit.id)

            // Delete habit
            try await container.habitService.deleteHabit(habit)

            await MainActor.run {
                dismiss()
            }
        } catch {
            // Handle error
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct HabitBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xxs)
            .background(color.opacity(0.15))
            .cornerRadius(SupportTheme.controlRadius)
    }
}

struct HabitStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
    }
}

struct WeeklyCompletionGrid: View {
    let stats: [Int]

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Circle()
                        .fill(stats[index] == 1 ? SupportTheme.accent : Color(uiColor: .tertiarySystemFill))
                        .frame(width: 32, height: 32)
                        .overlay(
                            stats[index] == 1
                                ? Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(SupportTheme.textPrimary)
                                : nil
                        )

                    Text(weekdays[index])
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String?
    var isDestructive: Bool = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isDestructive ? .red : SupportTheme.textSecondary)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(isDestructive ? .red : SupportTheme.textPrimary)

            Spacer()

            if let value = value {
                Text(value)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
    }
}

#Preview {
    let habit = Habit(
        id: UUID(),
        userId: UUID(),
        name: "Morning Meditation",
        anchor: "wake up",
        behavior: "meditate for 5 minutes",
        category: .meditation,
        difficulty: .easy,
        durationSeconds: 300,
        reminderTime: nil,
        reminderMinutesBefore: nil,
        isActive: true,
        createdAt: Date(),
        updatedAt: Date()
    )

    let streakInfo = HabitStreakInfo(
        currentStreak: 5,
        longestStreak: 10,
        lastCompletionDate: Date(),
        isCompletedToday: false,
        willResetNextDay: false
    )

    return NavigationStack {
        HabitDetailView(habit: habit, streakInfo: streakInfo)
            .environmentObject(DependencyContainer())
    }
}
