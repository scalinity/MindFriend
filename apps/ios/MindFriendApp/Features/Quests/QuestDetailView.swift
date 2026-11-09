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
                VStack(spacing: SupportTheme.Spacing.l) {
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
                .padding(SupportTheme.Spacing.m)
            }

            // Bottom action
            if quest.status != .completed {
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        showReflection = true
                    } label: {
                        Text("Complete Quest")
                    }
                    .buttonStyle(.supportPrimary)

                    Button {
                        skipQuest()
                    } label: {
                        Text("Skip for today")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minHeight: SupportTheme.minimumTarget)
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.canvas)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
        let capturedOwner = appState.currentUser?.id
        let capturedEpoch = appState.accountEpoch
        let submittedNote = reflectionNote.isEmpty ? nil : reflectionNote
        let submittedRating = rating > 0 ? rating : nil
        let ownerProof: @Sendable () async -> OfflineOwnerProof? = { @MainActor in
            guard let capturedOwner, appState.currentUser?.id == capturedOwner,
                  container.supabaseAuthService.userId == capturedOwner else { return nil }
            return OfflineOwnerProof(userId: capturedOwner, epoch: appState.accountEpoch)
        }
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
                guard let capturedOwner, let questID = UUID(uuidString: quest.id) else { throw DataError.invalidId }
                let owner = OfflineOwnerProof(userId: capturedOwner, epoch: capturedEpoch)
                let reward = try await AtomicCompletionRPC.completeQuest(client: container.supabaseClient,
                    owner: owner, ownerProof: ownerProof, questId: questID,
                    reflectionNote: submittedNote, rating: submittedRating)

                guard appState.currentUser?.id == owner.userId, appState.accountEpoch == owner.epoch else { throw CancellationError() }
                // The atomic RPC is the save acknowledgement. Optional refreshes cannot undo it.
                showReflection = false
                var completedQuest = quest
                completedQuest.status = .completed
                appState.todayQuest = completedQuest
                if reward.xpAwarded > 0 {
                    container.achievementService.triggerXPGainAnimation(amount: reward.xpAwarded, activity: .questComplete)
                }
                if reward.levelUp, let level = reward.newLevel, let title = reward.newTitle {
                    appState.showLevelUpCelebration(level: level, title: title)
                }
                completionResult = QuestCompletion(questId: quest.id, status: .completed, completedAt: Date(),
                    streakDays: appState.currentStreak, badgesEarned: [])
                DebtSourceChanges.saved()
                NotificationCenter.default.post(name: .todayQuestDidComplete, object: nil)
                isCompleting = false

                Task { @MainActor in
                    guard await ownerProof() == owner else { return }
                    if reward.xpAwarded > 0, let activityType = quest.template.type.eventActivityType {
                        _ = try? await container.supabaseDataService.incrementEventProgress(activityType: activityType)
                    }
                    guard await ownerProof() == owner else { return }
                    if let profile = try? await container.supabaseAuthService.fetchProfile() {
                        guard await ownerProof() == owner else { return }
                        appState.currentUser = profile
                        appState.currentStreak = profile.stats?.currentStreakDays ?? appState.currentStreak
                        completionResult = QuestCompletion(questId: quest.id, status: .completed,
                            completedAt: completionResult?.completedAt ?? Date(), streakDays: appState.currentStreak, badgesEarned: [])
                        if let milestones = try? await container.supabaseDataService.checkMilestoneTriggers(
                            streak: profile.stats?.currentStreakDays, questCount: profile.stats?.totalQuestsCompleted,
                            exerciseCount: nil, newLevel: reward.levelUp ? reward.newLevel : nil, badgeId: nil) {
                            guard await ownerProof() == owner else { return }
                            appState.addCelebrations(milestones.map { $0.toCelebrationEvent(userId: owner.userId) })
                        }
                    }
                    guard await ownerProof() == owner else { return }
                    _ = try? await container.achievementService.checkBadgeProgress()
                    guard await ownerProof() == owner else { return }
                    try? await container.activationService.recordQuestCompletion()
                }
            } catch {
                guard appState.currentUser?.id == capturedOwner, appState.accountEpoch == capturedEpoch else {
                    isCompleting = false; return
                }
                Log.quests.warning("Quest completion could not be confirmed")
                appState.showError(.apiError("Unable to save this quest. Your reflection is still here; please try again."))
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

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            if let arc = quest.arcContext {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    SupportRowLabel(title: arc.arcTitle,
                        subtitle: "Day \(arc.currentDay + 1) of \(arc.durationDays)", icon: "map")
                    ProgressView(value: min(1, max(0, arc.progressPercentage)))
                        .tint(SupportTheme.accent).accessibilityLabel("Journey progress")
                    if let milestone = arc.nextMilestone {
                        Label("Next milestone: day \(milestone)", systemImage: "flag")
                            .font(.caption).foregroundStyle(SupportTheme.textSecondary)
                    }
                    if let coaching = arc.coachingMessage {
                        Text(coaching).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                    }
                    if arc.isMilestoneDay {
                        Label("Milestone day", systemImage: "flag.fill").font(.headline)
                        Text("Complete to celebrate your progress")
                            .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(SupportTheme.separator)
            }
            Image(systemName: quest.template.type.icon)
                .font(.largeTitle).foregroundStyle(SupportTheme.accent).accessibilityHidden(true)
            Text(quest.template.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(quest.template.description).font(.body).foregroundStyle(SupportTheme.textSecondary)
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Label("\(quest.template.estimatedMinutes) min", systemImage: "clock")
                Label(quest.template.difficulty, systemImage: "speedometer")
            }
            .font(.caption).foregroundStyle(SupportTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .supportCard()
    }
}

struct QuestInstructions: View {
    let instructions: [QuestInstruction]
    @Binding var currentStep: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Instructions")
                .font(.headline).accessibilityAddTraits(.isHeader)

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
            HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(isCompleted || isActive ? SupportTheme.accent : SupportTheme.elevated)
                        .frame(width: 32, height: 32)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(SupportTheme.onAccent)
                    } else {
                        Text("\(instruction.step)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(isActive ? SupportTheme.onAccent : SupportTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(instruction.text)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let duration = instruction.durationSeconds {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(SupportTheme.Spacing.m)
            .background(isActive ? SupportTheme.elevated : SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
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
                .foregroundStyle(SupportTheme.accent)
            Text("Quest completed")
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.accent.opacity(0.1))
        .cornerRadius(SupportTheme.controlRadius)
    }
}

struct QuestReflectionSheet: View {
    let quest: Quest
    @Binding var reflectionNote: String
    @Binding var rating: Int
    @Binding var isCompleting: Bool
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    Text("A moment to reflect")
                        .font(.title2)
                        .fontWeight(.semibold).accessibilityAddTraits(.isHeader)

                    // Rating
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("How was this quest?")
                            .font(.headline)

                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(spacing: SupportTheme.Spacing.xs))
                            : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.xs))
                        layout {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title)
                                        .foregroundStyle(star <= rating ? SupportTheme.Celebration.gold : SupportTheme.textSecondary)
                                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                }
                                .accessibilityLabel("\(star) of 5 stars")
                                .accessibilityAddTraits(star == rating ? .isSelected : [])
                            }
                        }
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Reflection (optional)")
                            .font(.headline)

                        TextField("How do you feel after completing this?", text: $reflectionNote, axis: .vertical)
                            .supportField()
                            .lineLimit(3...6)
                    }

                    Text("\(reflectionNote.unicodeScalars.count) of 4,000 characters")
                        .font(.caption).foregroundStyle(SupportTheme.textSecondary)
                    if reflectionNote.unicodeScalars.count > 4_000 {
                        Text("Shorten this reflection before saving. Your text is still here.")
                            .font(.subheadline)
                    }
                    Button {
                        Log.quests.debug("[Quest] Save & Complete button tapped")
                        onComplete()
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            if isCompleting {
                                ProgressView()
                                    .tint(SupportTheme.onAccent)
                            }
                            Text(isCompleting ? "Completing..." : "Save & Complete")
                        }
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(isCompleting || reflectionNote.unicodeScalars.count > 4_000)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportSheet()
            .foregroundStyle(SupportTheme.textPrimary)
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
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
            CelebrationParticles().ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol("checkmark.seal.fill"), tint: SupportTheme.Celebration.gold, diameter: 112)
                    Text("Quest complete")
                        .font(.largeTitle.bold())
                        .foregroundStyle(SupportTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .celebrationReveal(delay: 0.2)
                    if !result.badgesEarned.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text("New badges").font(.headline).foregroundStyle(SupportTheme.textPrimary)
                            ForEach(result.badgesEarned) { badge in
                                Label(badge.title, systemImage: badge.icon)
                                    .foregroundStyle(SupportTheme.textPrimary)
                            }
                        }
                        .supportCard()
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .celebrationReveal(delay: 0.3)
                    }
                    Button("Continue", action: onDismiss)
                        .buttonStyle(.supportPrimary)
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .padding(.bottom, SupportTheme.Spacing.l)
                        .celebrationReveal(delay: 0.4)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(.top, SupportTheme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .supportSheet()
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Quest complete")).post() }
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
