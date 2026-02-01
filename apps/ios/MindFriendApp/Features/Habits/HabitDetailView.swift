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
        case .breathing: return .cyan
        case .meditation: return .purple
        case .journaling: return .orange
        case .movement: return .green
        case .custom: return .blue
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Text(categoryEmoji)
                        .font(.system(size: 60))

                    Text(habit.name)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(habit.fullHabitStatement)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Category and difficulty badges
                    HStack(spacing: 8) {
                        HabitBadge(text: habit.category.displayName, color: categoryColor)
                        HabitBadge(text: habit.difficulty.displayName, color: .gray)
                    }
                }
                .padding()

                // Stats section
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        HabitStatCard(
                            title: "Current Streak",
                            value: "\(streakInfo.currentStreak)",
                            icon: "flame.fill",
                            color: .orange
                        )

                        HabitStatCard(
                            title: "Longest Streak",
                            value: "\(streakInfo.longestStreak)",
                            icon: "trophy.fill",
                            color: .yellow
                        )
                    }

                    // Completion rate
                    let completionRate = weeklyStats.filter { $0 == 1 }.count
                    HStack(spacing: 20) {
                        HabitStatCard(
                            title: "This Week",
                            value: "\(completionRate)/7",
                            icon: "calendar",
                            color: .blue
                        )

                        HabitStatCard(
                            title: "Duration",
                            value: "\(habit.durationSeconds / 60)m",
                            icon: "clock.fill",
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal)

                // Weekly completion grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("This Week")
                        .font(.headline)

                    WeeklyCompletionGrid(stats: weeklyStats)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                // Complete button
                if !streakInfo.isCompletedToday {
                    Button {
                        Task { await completeHabit() }
                    } label: {
                        HStack {
                            if isCompleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Mark Complete")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(categoryColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isCompleting)
                    .padding(.horizontal)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Completed today!")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Settings section
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "bell.fill",
                        title: "Reminder",
                        value: habit.reminderTime != nil ? formatTime(habit.reminderTime!) : "Off"
                    )

                    Divider().padding(.leading, 44)

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
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 32)
            }
        }
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(8)
    }
}

struct HabitStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct WeeklyCompletionGrid: View {
    let stats: [Int]

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    Circle()
                        .fill(stats[index] == 1 ? Color.green : Color(uiColor: .tertiarySystemFill))
                        .frame(width: 32, height: 32)
                        .overlay(
                            stats[index] == 1
                            ? Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                            : nil
                        )

                    Text(weekdays[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(isDestructive ? .red : .secondary)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(isDestructive ? .red : .primary)

            Spacer()

            if let value = value {
                Text(value)
                    .foregroundStyle(.secondary)
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
