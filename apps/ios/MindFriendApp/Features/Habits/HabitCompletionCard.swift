import SwiftUI
import UIKit

// MARK: - Habit Completion Card

/// A card component displaying a habit with quick-complete functionality
struct HabitCompletionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        case .breathing: return SupportTheme.accent
        case .meditation: return SupportTheme.accent
        case .journaling: return SupportTheme.accent
        case .movement: return SupportTheme.accent
        case .custom: return SupportTheme.accent
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: SupportTheme.Spacing.s) {
                HStack(alignment: .top) {
                    // Category emoji + name
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Text(categoryEmoji)
                                .font(.title2)
                                .accessibilityAddTraits(.isHeader)
                            Text(habit.name)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundStyle(SupportTheme.textPrimary)
                        }

                        Text("After \(habit.anchor)")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                }

                // Completion button
                Button {
                    guard !isCompleting && !streakInfo.isCompletedToday else { return }
                    Task {
                        isCompleting = true
                        await onComplete()
                        withAnimation(
                            reduceMotion ? .easeInOut(duration: 0.2) : (.spring(response: 0.4, dampingFraction: 0.6))
                        ) {
                            showCompletedAnimation = true
                        }
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        isCompleting = false
                    }
                } label: {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        if isCompleting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(SupportTheme.textPrimary)
                        } else {
                            Image(systemName: streakInfo.isCompletedToday ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .scaleEffect(reduceMotion ? 1 : (showCompletedAnimation ? 1.2 : 1.0))
                        }
                        Text(streakInfo.isCompletedToday ? "Completed" : "Mark Complete")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.s)
                    .background(streakInfo.isCompletedToday ? SupportTheme.accent : categoryColor)
                    .foregroundStyle(SupportTheme.onAccent)
                    .cornerRadius(SupportTheme.controlRadius)
                }
                .disabled(isCompleting || streakInfo.isCompletedToday)
                .buttonStyle(.plain)
            }
            .supportCard()
            .overlay(
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .stroke(streakInfo.isCompletedToday ? SupportTheme.accent.opacity(0.3) : Color.clear, lineWidth: 2)
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
        HStack(spacing: SupportTheme.Spacing.s) {
            // Category indicator
            Text(categoryEmoji)
                .font(.title3)
                .accessibilityAddTraits(.isHeader)

            // Habit info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(habit.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(streakInfo.isCompletedToday ? "Completed today" : "Ready when you are")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

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
                            .foregroundStyle(
                                streakInfo.isCompletedToday ? SupportTheme.accent : SupportTheme.textSecondary)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
            .accessibilityLabel(streakInfo.isCompletedToday ? "Completed today" : "Mark Complete")
            .disabled(isCompleting || streakInfo.isCompletedToday)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.s)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header
                HStack {
                    Label("Today's Habits", systemImage: "repeat.circle.fill")
                        .font(.headline)

                    Spacer()

                    if totalCount > 0 {
                        Text("\(completedCount)/\(totalCount)")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, SupportTheme.Spacing.l)
                } else if habits.isEmpty {
                    // Empty state
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Build healthy habits")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textPrimary)
                            Text("Start with small, consistent actions")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(SupportTheme.accent)
                    }
                } else {
                    // Show up to 3 habits
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        ForEach(habits.prefix(3)) { habit in
                            CompactHabitCard(
                                habit: habit,
                                streakInfo: streakInfoMap[habit.id]
                                    ?? HabitStreakInfo(
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
                                .foregroundStyle(SupportTheme.accent)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .supportCard()
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
            Button("OK", role: .cancel) {}
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

    return VStack(spacing: SupportTheme.Spacing.m) {
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
