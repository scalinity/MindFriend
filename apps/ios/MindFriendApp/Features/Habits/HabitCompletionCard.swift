import SwiftUI
import UIKit

// MARK: - Habit Completion Card

/// A card component displaying a habit with quick-complete functionality
struct HabitCompletionCard: View {
    let habit: Habit
    let streakInfo: HabitStreakInfo
    let onComplete: () async -> Void
    let onTap: () -> Void

    @State private var isCompleting = false
    @State private var showCompletedAnimation = false

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
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    // Category emoji + name
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(categoryEmoji)
                                .font(.title2)
                            Text(habit.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }

                        Text("After \(habit.anchor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Streak indicator
                    if streakInfo.currentStreak > 0 {
                        HStack(spacing: 4) {
                            Text("🔥")
                            Text("\(streakInfo.currentStreak)")
                                .font(.title3.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Completion button
                Button {
                    guard !isCompleting && !streakInfo.isCompletedToday else { return }
                    Task {
                        isCompleting = true
                        await onComplete()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            showCompletedAnimation = true
                        }
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        isCompleting = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isCompleting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: streakInfo.isCompletedToday ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .scaleEffect(showCompletedAnimation ? 1.2 : 1.0)
                        }
                        Text(streakInfo.isCompletedToday ? "Completed" : "Mark Complete")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(streakInfo.isCompletedToday ? Color.green : categoryColor)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .disabled(isCompleting || streakInfo.isCompletedToday)
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(streakInfo.isCompletedToday ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Habit Card (for HomeView)

/// A compact card for displaying habits on the home screen
struct CompactHabitCard: View {
    let habit: Habit
    let streakInfo: HabitStreakInfo
    let onComplete: () async -> Void

    @State private var isCompleting = false

    private var categoryEmoji: String {
        switch habit.category {
        case .breathing: return "🫁"
        case .meditation: return "🧘"
        case .journaling: return "📝"
        case .movement: return "🏃"
        case .custom: return "✨"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category indicator
            Text(categoryEmoji)
                .font(.title3)

            // Habit info
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if streakInfo.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Text("🔥")
                            .font(.caption2)
                        Text("\(streakInfo.currentStreak) day streak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Complete button
            Button {
                guard !isCompleting && !streakInfo.isCompletedToday else { return }
                Task {
                    isCompleting = true
                    await onComplete()
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    isCompleting = false
                }
            } label: {
                Group {
                    if isCompleting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: streakInfo.isCompletedToday ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(streakInfo.isCompletedToday ? .green : .secondary)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .disabled(isCompleting || streakInfo.isCompletedToday)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Today's Habits Home Card

/// A home screen card showing today's habits to complete
struct TodaysHabitsHomeCard: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var habits: [Habit] = []
    @State private var streakInfoMap: [UUID: HabitStreakInfo] = [:]
    @State private var isLoading = true
    @State private var showHabitLibrary = false
    @State private var showCompletionError = false
    @State private var completionErrorMessage = ""

    private var completedCount: Int {
        streakInfoMap.values.filter { $0.isCompletedToday }.count
    }

    private var totalCount: Int {
        habits.count
    }

    var body: some View {
        Button {
            showHabitLibrary = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label("Today's Habits", systemImage: "repeat.circle.fill")
                        .font(.headline)

                    Spacer()

                    if totalCount > 0 {
                        Text("\(completedCount)/\(totalCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if habits.isEmpty {
                    // Empty state
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build healthy habits")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("Start with small, consistent actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    // Show up to 3 habits
                    VStack(spacing: 8) {
                        ForEach(habits.prefix(3)) { habit in
                            CompactHabitCard(
                                habit: habit,
                                streakInfo: streakInfoMap[habit.id] ?? HabitStreakInfo(
                                    currentStreak: 0,
                                    longestStreak: 0,
                                    lastCompletionDate: nil,
                                    isCompletedToday: false,
                                    willResetNextDay: false
                                ),
                                onComplete: {
                                    await completeHabit(habit)
                                }
                            )
                        }

                        if habits.count > 3 {
                            Text("View all \(habits.count) habits")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .task {
            await loadHabits()
        }
        .sheet(isPresented: $showHabitLibrary) {
            NavigationStack {
                HabitLibraryView()
                    .environmentObject(container)
            }
        }
        .alert("Couldn't Mark Complete", isPresented: $showCompletionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(completionErrorMessage)
        }
    }

    private func loadHabits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await container.habitService.fetchHabits()
            habits = container.habitService.habits

            // Load streak info for each habit
            for habit in habits {
                let info = try await container.habitService.getCurrentStreak(for: habit)
                streakInfoMap[habit.id] = info
            }
        } catch {
            #if DEBUG
            print("[TodaysHabitsHomeCard] loadHabits failed: \(error)")
            #endif
            habits = []
        }
    }

    private func completeHabit(_ habit: Habit) async {
        do {
            try await container.habitService.completeHabit(habit)
            // Refresh streak info
            let info = try await container.habitService.getCurrentStreak(for: habit)
            streakInfoMap[habit.id] = info

            // Check for streak milestone notifications
            if info.currentStreak > 0 && info.currentStreak % 7 == 0 {
                try? await container.habitNotificationService.scheduleStreakMilestoneNotification(
                    habit: habit,
                    streak: info.currentStreak,
                    milestone: info.currentStreak
                )
            }
        } catch {
            // Surface failures so the tap has visible feedback instead of
            // appearing to do nothing. Duplicate-completion is still treated
            // as a soft refresh since the habit is already complete today.
            #if DEBUG
            print("[HabitsSummaryCard] completeHabit failed: \(error)")
            #endif
            if case HabitServiceError.duplicateCompletion = error {
                if let info = try? await container.habitService.getCurrentStreak(for: habit) {
                    streakInfoMap[habit.id] = info
                }
            } else {
                completionErrorMessage = error.localizedDescription
                showCompletionError = true
            }
        }
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

    return VStack(spacing: 16) {
        HabitCompletionCard(
            habit: habit,
            streakInfo: streakInfo,
            onComplete: {},
            onTap: {}
        )

        CompactHabitCard(
            habit: habit,
            streakInfo: streakInfo,
            onComplete: {}
        )
    }
    .padding()
}
