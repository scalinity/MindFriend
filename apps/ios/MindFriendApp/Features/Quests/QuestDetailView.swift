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
                isCompleting: $isCompleting,
                onComplete: completeQuest
            )
        }
        .sheet(item: $completionResult) { result in
            QuestCompletionCelebration(result: result, onDismiss: { dismiss() })
        }
    }

    private func completeQuest() {
        Log.quests.debug("[Quest] completeQuest() called")
        guard !isCompleting else { return }
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

                // Trigger XP gain toast IMMEDIATELY for instant gratification
                await MainActor.run {
                    container.achievementService.triggerXPGainAnimation(
                        amount: xpResult.amount,
                        activity: .questComplete
                    )
                }

                // Update event progress for quest-related activities
                if let activityType = quest.template.type.eventActivityType {
                    _ = try? await container.supabaseDataService.incrementEventProgress(activityType: activityType)
                }

                // Fetch updated profile to get new streak
                let profile = try await container.supabaseAuthService.fetchProfile()

                // Check for milestone celebrations
                let milestoneCelebrations = try await container.supabaseDataService.checkMilestoneTriggers(
                    streak: profile.stats?.currentStreakDays ?? 0,
                    questCount: profile.stats?.totalQuestsCompleted ?? 0,
                    exerciseCount: nil,
                    newLevel: xpResult.leveledUp ? xpResult.newLevel : nil,
                    badgeId: nil
                )

                // Fire-and-forget: badge check and activation record run in background
                // These are slow operations that shouldn't block the UI
                let achievementService = container.achievementService
                let activationService = container.activationService
                Task.detached(priority: .utility) {
                    _ = try? await achievementService.checkBadgeProgress()
                    try? await activationService.recordQuestCompletion()
                }

                await MainActor.run {
                    appState.currentStreak = profile.stats?.currentStreakDays ?? 0
                    appState.currentUser = profile
                    showReflection = false

                    // Update todayQuest with completed status so HomeView reflects it immediately
                    var completedQuest = quest
                    completedQuest.status = .completed
                    appState.todayQuest = completedQuest

                    // Show level-up celebration if leveled up (legacy celebration for immediate feedback)
                    if xpResult.leveledUp {
                        appState.showLevelUpCelebration(level: xpResult.newLevel, title: xpResult.newTitle)
                    }

                    // Queue milestone celebrations (shown after level-up if both occur)
                    if !milestoneCelebrations.isEmpty {
                        let celebrations = milestoneCelebrations.map { $0.toCelebrationEvent(userId: profile.id) }
                        appState.addCelebrations(celebrations)
                    }

                    // Create completion result for display
                    completionResult = QuestCompletion(
                        questId: quest.id,
                        status: .completed,
                        completedAt: Date(),
                        streakDays: profile.stats?.currentStreakDays ?? 0,
                        badgesEarned: []
                    )

                    // Signal HomeView to refresh shield/streak status so the
                    // streak card doesn't keep showing stale data from before
                    // this completion (e.g. "Start your streak!" after 1-day).
                    NotificationCenter.default.post(name: .todayQuestDidComplete, object: nil)
                }
            } catch {
                Log.quests.error("QuestDetailView completeQuest error", error: error)
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
            let currentStats = user.stats ?? UserStats(currentStreakDays: 0, longestStreakDays: 0, totalQuestsCompleted: 0, totalExercisesCompleted: 0)
            user = UserProfile(
                id: user.id,
                handle: user.handle,
                displayName: user.displayName,
                email: user.email,
                avatarUrl: user.avatarUrl,
                timezone: user.timezone,
                createdAt: user.createdAt,
                onboardingCompletedAt: user.onboardingCompletedAt,
                stats: UserStats(
                    currentStreakDays: newStreak,
                    longestStreakDays: max(currentStats.longestStreakDays, newStreak),
                    totalQuestsCompleted: currentStats.totalQuestsCompleted + 1,
                    totalExercisesCompleted: currentStats.totalExercisesCompleted
                ),
                settings: user.settings,
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
                Log.quests.error("QuestDetailView skipQuest error", error: error)
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

struct QuestHeader: View {
    let quest: Quest

    /// Color for the journey category
    private var journeyColor: Color {
        guard let arc = quest.arcContext else { return .accentColor }
        switch arc.arcCategory.lowercased() {
        case "stress": return .blue
        case "sleep": return .indigo
        case "confidence": return .purple
        case "focus": return .teal
        case "resilience": return .green
        default: return .accentColor
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Journey context banner (if part of a journey)
            if let arc = quest.arcContext {
                VStack(spacing: 12) {
                    // Journey header
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundStyle(journeyColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(arc.arcTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(journeyColor)
                            Text("Day \(arc.currentDay + 1) of \(arc.durationDays)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        // Next milestone indicator
                        if let nextMilestone = arc.nextMilestone {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Next Milestone")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Image(systemName: "flag.fill")
                                        .font(.caption)
                                    Text("Day \(nextMilestone)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(journeyColor)
                                .frame(width: geometry.size.width * arc.progressPercentage, height: 8)

                            // Milestone markers
                            ForEach(arc.milestoneDays, id: \.self) { milestone in
                                let position = Double(milestone) / Double(arc.durationDays)
                                Circle()
                                    .fill(milestone <= arc.currentDay ? journeyColor : Color(.systemGray4))
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.white)
                                    )
                                    .offset(x: (geometry.size.width * position) - 6)
                            }
                        }
                    }
                    .frame(height: 12)

                    // Coaching message
                    if let coaching = arc.coachingMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(journeyColor)
                            Text(coaching)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(journeyColor.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Milestone day banner
                    if arc.isMilestoneDay {
                        HStack(spacing: 8) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.yellow)
                            Text("Milestone Day!")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Complete to celebrate your progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.yellow.opacity(0.2), .orange.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(journeyColor.opacity(0.05))
                .cornerRadius(12)
            }

            // Quest icon
            Image(systemName: quest.template.type.icon)
                .font(.system(size: 50))
                .foregroundStyle(quest.isPartOfJourney ? journeyColor : Color.accentColor)

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
                        Text(formatDuration(duration))
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

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) sec"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds == 0 {
                return "\(minutes) min"
            } else {
                return "\(minutes)m \(remainingSeconds)s"
            }
        }
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
    @Binding var isCompleting: Bool
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
                        HStack(spacing: 8) {
                            if isCompleting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isCompleting ? "Completing..." : "Save & Complete")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isCompleting ? Color.accentColor.opacity(0.6) : Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isCompleting)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDoneButton()
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
            completedAt: nil,
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
