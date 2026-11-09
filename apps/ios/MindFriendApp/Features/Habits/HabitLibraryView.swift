import SwiftUI

// MARK: - Habit Library View

/// Main view for browsing and managing user's habits
struct HabitLibraryView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @State private var habits: [Habit] = []
    @State private var streakInfoMap: [UUID: HabitStreakInfo] = [:]
    @State private var isLoading = true
    @State private var selectedCategory: HabitCategory?
    @State private var showCreateSheet = false
    @State private var selectedHabit: Habit?
    @State private var sortOption: SortOption = .name

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case recent = "Recent"
    }

    private var filteredHabits: [Habit] {
        var result = habits

        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        // Sort
        switch sortOption {
        case .name:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .recent:
            result.sort { $0.createdAt > $1.createdAt }
        }

        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Create habit button
                Button {
                    showCreateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Create New Habit")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding()
                    .background(SupportTheme.surface)
                    .foregroundStyle(SupportTheme.accent)
                    .cornerRadius(SupportTheme.controlRadius)
                }
                .buttonStyle(.plain)

                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        FilterChip(
                            label: "All",
                            isSelected: selectedCategory == nil,
                            action: { selectedCategory = nil }
                        )

                        ForEach(HabitCategory.allCases, id: \.self) { category in
                            FilterChip(
                                label: category.displayName,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                }

                // Sort picker
                HStack {
                    Text("Sort by")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                // Habit list
                if isLoading {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        ProgressView()
                        Text("Loading habits...")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                } else if filteredHabits.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(filteredHabits) { habit in
                            HabitCompletionCard(
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
                                },
                                onTap: {
                                    selectedHabit = habit
                                }
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("My Habits")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                CreateHabitView()
                    .environmentObject(container)
            }
        }
        .sheet(item: $selectedHabit) { habit in
            NavigationStack {
                HabitDetailView(
                    habit: habit,
                    streakInfo: streakInfoMap[habit.id]
                        ?? HabitStreakInfo(
                            currentStreak: 0,
                            longestStreak: 0,
                            lastCompletionDate: nil,
                            isCompletedToday: false,
                            willResetNextDay: false
                        )
                )
                .environmentObject(container)
            }
        }
        .task {
            await loadHabits()
        }
        .refreshable {
            await loadHabits()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 50))
                .foregroundStyle(SupportTheme.textSecondary)

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text("No Habits Yet")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(
                    selectedCategory != nil
                        ? "No \(selectedCategory!.displayName.lowercased()) habits found"
                        : "Create your first habit to start building healthy routines"
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
            }

            Button {
                showCreateSheet = true
            } label: {
                Label("Create Habit", systemImage: "plus")
            }
            .buttonStyle(.supportPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xl)
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
            habits = []
        }
    }

    private func completeHabit(_ habit: Habit) async {
        do {
            try await container.habitService.completeHabit(habit)
            let info = try await container.habitService.getCurrentStreak(for: habit)
            streakInfoMap[habit.id] = info

            // Check for streak milestone
            if info.currentStreak > 0 && info.currentStreak % 7 == 0 {
                try? await container.habitNotificationService.scheduleStreakMilestoneNotification(
                    habit: habit,
                    streak: info.currentStreak,
                    milestone: info.currentStreak
                )
            }
        } catch {
            // Handle error
        }
    }
}

#Preview {
    NavigationStack {
        HabitLibraryView()
            .environmentObject(DependencyContainer())
    }
}
