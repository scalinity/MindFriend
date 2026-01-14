import SwiftUI
import OSLog

struct QuestDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let quest: Quest
    @State private var currentStep = 0
    @State private var isCompleting = false
    @State private var showReflection = false
    @State private var reflectionNote = ""
    @State private var rating: Int = 0
    @State private var completionResult: QuestCompletion?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Quest header
                    QuestHeader(quest: quest)

                    if quest.status == .completed {
                        CompletedBanner()
                    } else {
                        // Instructions
                        QuestInstructions(
                            instructions: quest.template.instructions,
                            currentStep: $currentStep
                        )
                    }
                }
                .padding()
            }

            // Bottom action
            if quest.status != .completed {
                VStack(spacing: 12) {
                    Button {
                        showReflection = true
                    } label: {
                        Text("Complete Quest")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        skipQuest()
                    } label: {
                        Text("Skip for today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(quest.template.type.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReflection) {
            QuestReflectionSheet(
                quest: quest,
                reflectionNote: $reflectionNote,
                rating: $rating,
                onComplete: completeQuest
            )
        }
        .sheet(item: $completionResult) { result in
            QuestCompletionCelebration(result: result, onDismiss: { dismiss() })
        }
    }

    private func completeQuest() {
        Log.quests.debug("[Quest] completeQuest() called")
        isCompleting = true

        Task { @MainActor in
            Log.quests.debug("[Quest] Task started")
            // Check if we're in dev mode (no real Supabase session)
            let isDevMode = container.supabaseAuthService.userId == nil
            Log.quests.debug("[Quest] isDevMode: \(isDevMode)")

            if isDevMode {
                #if DEBUG
                Log.quests.debug("[Quest] Calling completeQuestInDevMode()")
                await completeQuestInDevMode()
                Log.quests.debug("[Quest] completeQuestInDevMode() finished")
                #else
                appState.showError(.apiError("Please sign in to complete quests"))
                #endif
                isCompleting = false
                return
            }

            do {
                try await container.supabaseDataService.completeQuest(
                    id: quest.id,
                    reflectionNote: reflectionNote.isEmpty ? nil : reflectionNote,
                    rating: rating > 0 ? rating : nil
                )

                // Award XP for quest completion
                let xpResult = try await container.supabaseDataService.awardXP(activity: .questComplete)

                // Update event progress for quest-related activities
                if let activityType = quest.template.type.eventActivityType {
                    _ = try? await container.supabaseDataService.incrementEventProgress(activityType: activityType)
                }

                // Fetch updated profile to get new streak
                let profile = try await container.supabaseAuthService.fetchProfile()

                await MainActor.run {
                    appState.currentStreak = profile.stats.currentStreakDays
                    appState.currentUser = profile
                    showReflection = false

                    // Show level-up celebration if leveled up
                    if xpResult.leveledUp {
                        appState.showLevelUpCelebration(level: xpResult.newLevel, title: xpResult.newTitle)
                    }

                    // Create completion result for display
                    completionResult = QuestCompletion(
                        questId: quest.id,
                        status: .completed,
                        completedAt: Date(),
                        streakDays: profile.stats.currentStreakDays,
                        badgesEarned: []
                    )
                }
            } catch {
                print("QuestDetailView completeQuest error: \(error)")
                appState.showError(.apiError(error.localizedDescription))
            }
            isCompleting = false
        }
    }

    #if DEBUG
    private func completeQuestInDevMode() async {
        Log.quests.debug("[Quest] completeQuestInDevMode started")

        // Update streak in dev mode
        let newStreak = appState.currentStreak + 1
        appState.currentStreak = newStreak
        Log.quests.debug("[Quest] Updated streak to \(newStreak)")

        // Update user stats
        if var user = appState.currentUser {
            user = UserProfile(
                id: user.id,
                handle: user.handle,
                displayName: user.displayName,
                email: user.email,
                timezone: user.timezone,
                createdAt: user.createdAt,
                settings: user.settings,
                stats: UserStats(
                    currentStreakDays: newStreak,
                    longestStreakDays: max(user.stats.longestStreakDays, newStreak),
                    totalQuestsCompleted: user.stats.totalQuestsCompleted + 1,
                    totalExercisesCompleted: user.stats.totalExercisesCompleted
                ),
                entitlements: user.entitlements,
                badges: user.badges
            )
            appState.currentUser = user
            Log.quests.debug("[Quest] Updated user stats")
        }

        // Mark quest as completed locally
        if var todayQuest = appState.todayQuest, todayQuest.id == quest.id {
            todayQuest = Quest(
                id: todayQuest.id,
                localDate: todayQuest.localDate,
                status: .completed,
                assignedAt: todayQuest.assignedAt,
                completedAt: Date(),
                template: todayQuest.template
            )
            appState.todayQuest = todayQuest
            Log.quests.debug("[Quest] Marked quest as completed")
        }

        // Dismiss reflection sheet first
        showReflection = false
        Log.quests.debug("[Quest] Dismissed reflection sheet")

        // Wait for sheet dismissal animation
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Then show celebration
        completionResult = QuestCompletion(
            questId: quest.id,
            status: .completed,
            completedAt: Date(),
            streakDays: newStreak,
            badgesEarned: []
        )
        Log.quests.debug("[Quest] Set completionResult to show celebration")
    }
    #endif

    private func skipQuest() {
        Task {
            // Check if we're in dev mode
            let isDevMode = container.supabaseAuthService.userId == nil

            if isDevMode {
                #if DEBUG
                await MainActor.run {
                    appState.currentStreak = 0
                    if var todayQuest = appState.todayQuest, todayQuest.id == quest.id {
                        todayQuest = Quest(
                            id: todayQuest.id,
                            localDate: todayQuest.localDate,
                            status: .skipped,
                            assignedAt: todayQuest.assignedAt,
                            completedAt: nil,
                            template: todayQuest.template
                        )
                        appState.todayQuest = todayQuest
                    }
                    dismiss()
                }
                #endif
                return
            }

            do {
                try await container.supabaseDataService.skipQuest(id: quest.id)
                await MainActor.run {
                    appState.currentStreak = 0
                    dismiss()
                }
            } catch {
                print("QuestDetailView skipQuest error: \(error)")
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

struct QuestHeader: View {
    let quest: Quest

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: quest.template.type.icon)
                .font(.system(size: 50))
                .foregroundStyle(Color.accentColor)

            Text(quest.template.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(quest.template.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Label("\(quest.template.estimatedMinutes) min", systemImage: "clock")
                Label(quest.template.difficulty, systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestInstructions: View {
    let instructions: [QuestInstruction]
    @Binding var currentStep: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instructions")
                .font(.headline)

            ForEach(instructions.indices, id: \.self) { index in
                InstructionRow(
                    instruction: instructions[index],
                    isActive: index == currentStep,
                    isCompleted: index < currentStep,
                    onTap: { currentStep = index }
                )
            }
        }
    }
}

struct InstructionRow: View {
    let instruction: QuestInstruction
    let isActive: Bool
    let isCompleted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green : (isActive ? Color.accentColor : Color.secondary.opacity(0.3)))
                        .frame(width: 32, height: 32)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    } else {
                        Text("\(instruction.step)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(isActive ? .white : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(instruction.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let duration = instruction.durationSeconds {
                        Text("\(duration / 60) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(isActive ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct CompletedBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Quest completed!")
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct QuestReflectionSheet: View {
    let quest: Quest
    @Binding var reflectionNote: String
    @Binding var rating: Int
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Great job completing your quest!")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Rating
                    VStack(spacing: 12) {
                        Text("How was this quest?")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title)
                                        .foregroundStyle(star <= rating ? .yellow : .secondary)
                                }
                            }
                        }
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflection (optional)")
                            .font(.headline)

                        TextField("How do you feel after completing this?", text: $reflectionNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    Button {
                        Log.quests.debug("[Quest] Save & Complete button tapped")
                        onComplete()
                    } label: {
                        Text("Save & Complete")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct QuestCompletionCelebration: View {
    let result: QuestCompletion
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "party.popper.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Quest Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(result.streakDays) day streak!")
                        .font(.title2)
                }

                if !result.badgesEarned.isEmpty {
                    Text("New badges earned:")
                        .font(.headline)
                        .padding(.top)

                    ForEach(result.badgesEarned) { badge in
                        HStack {
                            Image(systemName: badge.icon)
                                .foregroundStyle(.yellow)
                            Text(badge.title)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
    }
}

extension QuestCompletion: Identifiable {
    var id: String { questId }
}

#Preview {
    NavigationStack {
        QuestDetailView(quest: Quest(
            id: "1",
            localDate: "2024-01-15",
            status: .assigned,
            assignedAt: Date(),
            template: QuestTemplate(
                id: "t1",
                type: .breathing,
                title: "4-7-8 Breathing",
                description: "A calming breathing technique to reduce stress",
                estimatedMinutes: 5,
                difficulty: "easy",
                tags: ["calming", "stress-relief"],
                instructions: [
                    QuestInstruction(step: 1, text: "Find a comfortable seated position", durationSeconds: nil),
                    QuestInstruction(step: 2, text: "Breathe in through your nose for 4 seconds", durationSeconds: 4),
                    QuestInstruction(step: 3, text: "Hold your breath for 7 seconds", durationSeconds: 7),
                    QuestInstruction(step: 4, text: "Exhale slowly through your mouth for 8 seconds", durationSeconds: 8),
                    QuestInstruction(step: 5, text: "Repeat 4 times", durationSeconds: nil)
                ]
            )
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
