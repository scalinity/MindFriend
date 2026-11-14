import SwiftUI

extension ExerciseType {
    /// 1.0.5 category colors: breathing blue, meditation purple, grounding green,
    /// journaling orange, movement pink.
    var categoryArea: SupportTheme.Area {
        switch self {
        case .breathing: return .exercises
        case .meditation: return .journal
        case .grounding: return .insights
        case .journaling: return .quests
        case .movement: return .people
        }
    }
}

struct ExerciseLibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var exercises: [Exercise] = []
    @State private var skillProgress: [SkillProgress] = []
    @State private var selectedType: ExerciseType?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showOnlyRecommended = false
    @State private var showGenerateExercise = false
    @State private var showSavedExercises = false

    // Exercises tutorial state
    @AppStorage("exercises_tutorial_completed") private var exercisesTutorialCompleted = false
    @State private var showExercisesTutorial = false

    var filteredExercises: [Exercise] {
        var filtered = exercises

        // Filter by type
        if let type = selectedType {
            filtered = filtered.filter { $0.type == type }
        }

        // Filter by recommended (capacity-based)
        if showOnlyRecommended {
            filtered = filtered.filter { isRecommended($0) }
        }

        // Sort: recommended first
        return filtered.sorted { isRecommended($0) && !isRecommended($1) }
    }

    /// Check if exercise is recommended for current capacity level
    /// Uses rounded duration to avoid integer truncation issues (e.g., 90s = 2min not 1min)
    private func isRecommended(_ exercise: Exercise) -> Bool {
        let level = container.difficultyService.getEffectiveLevel()
        // Round up to nearest minute to avoid truncation
        let duration = (exercise.durationSeconds + 30) / 60

        switch level {
        case .low:
            // Rest Mode: Short calming exercises (any type ≤5 min, or breathing/grounding up to 8 min)
            if duration <= 5 {
                return true // Any short exercise is good for rest
            }
            return duration <= 8 && (exercise.type == .breathing || exercise.type == .grounding)
        case .moderate:
            // Normal Mode: Medium duration (5-15 min), all types welcome
            return duration >= 5 && duration <= 15
        case .high:
            // Challenge Mode: Longer exercises (10+ min), all types
            return duration >= 10
        }
    }

    /// Get skill progress for the selected type
    var selectedSkillProgress: SkillProgress? {
        guard let type = selectedType else { return nil }
        return skillProgress.first { $0.skillType == type }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.m) {
                // AI-Generated Exercise Actions
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        showGenerateExercise = true
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title3)
                            Text("Generate New Exercise")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .padding(SupportTheme.Spacing.m)
                        .background(SupportTheme.surface)
                        .foregroundStyle(SupportTheme.Area.exercises.palette.ink)
                        .cornerRadius(SupportTheme.controlRadius)
                    }

                    Button {
                        showSavedExercises = true
                    } label: {
                        HStack {
                            Image(systemName: "heart.text.square")
                                .font(.title3)
                            Text("My Saved Exercises")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .padding(SupportTheme.Spacing.m)
                        .background(SupportTheme.surface)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .cornerRadius(SupportTheme.controlRadius)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                Divider()
                    .padding(.vertical, SupportTheme.Spacing.xs)

                // Type filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ExerciseFilterChip(
                            title: "All",
                            area: .exercises,
                            isSelected: selectedType == nil,
                            action: { selectedType = nil }
                        )

                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            ExerciseFilterChip(
                                title: type.rawValue.capitalized,
                                icon: type.icon,
                                area: type.categoryArea,
                                isSelected: selectedType == type,
                                action: { selectedType = type }
                            )
                        }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }

                // Recommended filter
                Toggle("Show only recommended for you", isOn: $showOnlyRecommended)
                    .font(.subheadline)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Skill progress indicator (shown when a type is selected)
                if let skill = selectedSkillProgress {
                    SkillIndicatorView(
                        skillType: skill.skillType,
                        level: skill.skillLevel,
                        xp: skill.xp
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else if selectedType != nil {
                    // Show starter indicator for types with no progress
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                        Text("Complete exercises to level up this skill")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.separator)
                    .cornerRadius(SupportTheme.controlRadius)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                // Exercises
                if isLoading {
                    ProgressView()
                        .padding(.top, SupportTheme.Spacing.xl)
                } else if let loadError {
                        SupportUnavailableState(title: "Exercises unavailable", message: loadError, actionTitle: "Try again") {
                            Task { await loadExercises() }
                        }
                    } else if filteredExercises.isEmpty {
                    Text("No exercises found")
                        .foregroundStyle(SupportTheme.textSecondary)
                        .padding(.top, SupportTheme.Spacing.xl)
                } else {
                    LazyVStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(filteredExercises) { exercise in
                            NavigationLink {
                                LibraryExercisePlayerView(exercise: exercise, container: container)
                            } label: {
                                ExerciseCard(
                                    exercise: exercise,
                                    isRecommended: isRecommended(exercise)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
        .scrollClipDisabled(false)
        .supportScreen()
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)

        // Load exercises on appear
        .task {
            await loadExercises()
        }
        .sheet(isPresented: $showGenerateExercise) {
            GenerateExerciseView(container: container)
        }
        .sheet(isPresented: $showSavedExercises) {
            SavedExercisesView(container: container)
        }
        .onAppear {
            if !exercisesTutorialCompleted {
                showExercisesTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showExercisesTutorial) {
            ExerciseTutorialFlow(onComplete: {
                exercisesTutorialCompleted = true
                showExercisesTutorial = false
            })
            .environmentObject(container)
        }
        .skillLevelUpCelebration()
    }

    private func loadExercises() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            async let exercisesTask = container.supabaseDataService.getExercises()
            async let skillsTask = container.supabaseDataService.getSkillProgress()

            exercises = try await exercisesTask
            skillProgress = try await skillsTask
        } catch {
            Log.quests.error("ExerciseLibraryView loadExercises error", error: error)
            loadError = error.localizedDescription
        }
    }
}

private struct ExerciseFilterChip: View {
    let title: String
    var icon: String?
    let area: SupportTheme.Area
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background {
                if isSelected {
                    area.palette.heroGradient
                } else {
                    SupportTheme.surface
                }
            }
            .foregroundStyle(isSelected ? SupportTheme.onHero : SupportTheme.textPrimary)
            .cornerRadius(SupportTheme.cardRadius)
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    var isRecommended: Bool = false

    private var durationMinutes: Int {
        guard exercise.durationSeconds > 0 else { return 0 }
        return exercise.durationSeconds / 60
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Icon - fixed size
            Image(systemName: exercise.type.icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.onHero)
                .frame(width: 50, height: 50)
                .background(exercise.type.categoryArea.palette.heroGradient)
                .cornerRadius(SupportTheme.controlRadius)
                .accessibilityHidden(true)

            // Content - flexible, takes remaining space
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                // Title row
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Text(exercise.title)
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .fixedSize(horizontal: false, vertical: true)

                    if isRecommended {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(exercise.type.categoryArea.palette.ink)
                    }
                }

                // Description
                Text(exercise.description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Metadata row - wrap to fit
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Label("\(durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if let basis = exercise.evidenceBasis {
                        EvidenceBadge(
                            basis: basis,
                            isReviewed: exercise.isTherapistReviewed,
                            showInfo: false
                        )
                    }

                    if isRecommended {
                        Text("For you")
                            .font(.caption2)
                            .padding(.horizontal, SupportTheme.Spacing.xxs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(exercise.type.categoryArea.palette.tint)
                            .foregroundColor(exercise.type.categoryArea.palette.ink)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(SupportTheme.Spacing.s)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to start this exercise")
    }

    private var accessibilityDescription: String {
        var description = "\(exercise.title), \(exercise.type.rawValue) exercise, \(durationMinutes) minutes"
        if let basis = exercise.evidenceBasis {
            description += ", based on \(basis.displayName)"
            if exercise.isTherapistReviewed {
                description += ", reviewed by mental health professionals"
            }
        }
        return description
    }
}

struct ExercisePlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase  // Background handling

    let exercise: Exercise
    @State private var session: ExerciseSession?
    @State private var isPlaying = false
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var showCompletion = false
    @State private var rating: Int = 0
    @State private var isStartingSession = false
    @State private var isSubmittingCompletion = false
    @State private var completionError: String?
    @State private var wasPlayingBeforeBackground = false  // Track state for resume

    // Efficacy tracking
    @State private var isTrackingEfficacy = false
    @State private var currentTrajectory: [TrajectoryPoint] = []
    @State private var showBreakthroughCelebration = false
    @State private var breakthroughSecond: Int?
    @State private var efficacyResult: InterventionEfficacy?

    init(exercise: Exercise) {
        self.exercise = exercise
        _timeRemaining = State(initialValue: exercise.durationSeconds)
    }

    var progress: Double {
        guard exercise.durationSeconds > 0 else { return 0 }
        return 1.0 - (Double(timeRemaining) / Double(exercise.durationSeconds))
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xl) {
            Spacer()

            // Timer circle
            ZStack {
                Circle()
                    .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(exercise.type.categoryArea.palette.ink, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)

                VStack {
                    Text(timeString)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)  // Support Dynamic Type

                    Text(isPlaying ? "In Progress" : "Ready")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Timer: \(timeString), \(isPlaying ? "in progress" : "ready")")
            }
            .frame(width: 250, height: 250)

            // Trajectory visualization (shown during exercise)
            if isTrackingEfficacy && !currentTrajectory.isEmpty {
                TrajectoryVisualizationView(
                    trajectory: currentTrajectory,
                    isLive: isPlaying
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            // Exercise content
            if let text = exercise.contentText {
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Spacer()

            // Controls
            HStack(spacing: SupportTheme.Spacing.xl) {
                Button {
                    resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Restart")
                }
                .disabled(!isPlaying && timeRemaining == exercise.durationSeconds)

                Button {
                    if isPlaying {
                        pauseTimer()
                    } else {
                        startTimer()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(exercise.type.categoryArea.palette.ink)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel(isPlaying ? "Pause" : "Play")
                }

                Button {
                    completeExercise()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Complete exercise")
                }
            }
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
        .supportScreen()
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCompletion) {
            ExerciseCompletionView(
                rating: $rating, isSubmitting: isSubmittingCompletion, errorMessage: completionError
            ) {
                submitCompletion()
            }
        }
        .fullScreenCover(isPresented: $showBreakthroughCelebration) {
            BreakthroughCelebrationView(breakthroughSecond: breakthroughSecond) {
                showBreakthroughCelebration = false
            }
        }
        .task {
            await startSession()
        }
        .onReceive(container.interventionEfficacyEngine.tracker.$currentTrajectory) { trajectory in
            currentTrajectory = trajectory
            checkForBreakthrough()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Handle app going to background - pause timer to save battery and state
            switch newPhase {
            case .background, .inactive:
                if isPlaying {
                    wasPlayingBeforeBackground = true
                    pauseTimer()
                }
            case .active:
                // Optionally auto-resume when returning to foreground
                // Currently we keep it paused so user can resume when ready
                break
            @unknown default:
                break
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            // Stop tracking if still active
            if isTrackingEfficacy {
                Task {
                    await stopEfficacyTracking()
                }
            }
        }
    }

    var timeString: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startSession() async {
        guard session == nil, !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }
        do {
            let sessionId = try await container.supabaseDataService.startExerciseSession(exerciseId: exercise.id)
            session = ExerciseSession(id: sessionId, exerciseId: exercise.id, startedAt: Date(), endedAt: nil, completed: false)
        } catch {
            // Session tracking is optional - log but allow exercise to continue
            Log.quests.warning("Failed to start exercise session: \(error.localizedDescription)")
        }
    }

    private func startTimer() {
        isPlaying = true

        // Start efficacy tracking
        Task {
            await startEfficacyTracking()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                completeExercise()
            }
        }
    }

    private func pauseTimer() {
        isPlaying = false
        timer?.invalidate()
    }

    private func resetTimer() {
        pauseTimer()
        timeRemaining = exercise.durationSeconds

        // Reset efficacy tracking
        Task {
            if isTrackingEfficacy {
                await stopEfficacyTracking()
            }
            isTrackingEfficacy = false
            currentTrajectory = []
            efficacyResult = nil
        }
    }

    private func completeExercise() {
        pauseTimer()

        // Stop efficacy tracking
        Task {
            await stopEfficacyTracking()
            showCompletion = true
        }
    }

    // MARK: - Efficacy Tracking

    private func startEfficacyTracking() async {
        guard let session = session,
              let sessionIdUUID = UUID(uuidString: session.id),
              let exerciseIdUUID = UUID(uuidString: exercise.id) else { return }

        do {
            // Get user ID from Supabase session
            let supabaseSession = try await container.supabase.auth.session
            let userId = supabaseSession.user.id

            try await container.interventionEfficacyEngine.startSession(
                sessionId: sessionIdUUID,
                exerciseId: exerciseIdUUID,
                userId: userId
            )
            await MainActor.run {
                isTrackingEfficacy = true
            }
        } catch {
            Log.quests.warning("Failed to start efficacy tracking: \(error.localizedDescription)")
        }
    }

    private func stopEfficacyTracking() async {
        guard isTrackingEfficacy else { return }

        do {
            efficacyResult = try await container.interventionEfficacyEngine.endSession()
            await MainActor.run {
                isTrackingEfficacy = false
            }
        } catch {
            Log.quests.warning("Failed to stop efficacy tracking: \(error.localizedDescription)")
            await MainActor.run {
                isTrackingEfficacy = false
            }
        }
    }

    private func checkForBreakthrough() {
        guard currentTrajectory.count >= 2 else { return }

        let lastIndex = currentTrajectory.count - 1
        let current = currentTrajectory[lastIndex]
        let previous = currentTrajectory[lastIndex - 1]

        let change = current.compositeScore - previous.compositeScore
        let duration = current.secondsFromStart - previous.secondsFromStart

        if change > 0.4 && duration <= 60 {
            breakthroughSecond = current.secondsFromStart
            showBreakthroughCelebration = true
        }
    }

    private func submitCompletion() {
        guard !isSubmittingCompletion else { return }
        isSubmittingCompletion = true
        completionError = nil
        Task {
            defer { isSubmittingCompletion = false }
            do {
                if session == nil { await startSession() }
                guard let session else {
                    throw DataError.operationFailed("The exercise session could not be started. Please retry.")
                }
                try await container.supabaseDataService.completeExerciseSession(
                    sessionId: session.id, rating: rating > 0 ? rating : nil, note: nil
                )
                let xpResult = try await container.supabaseDataService.awardXP(
                    activity: .exerciseComplete(exercise.type), exerciseSessionId: session.id
                )
                if xpResult.amount > 0 {
                    container.achievementService.triggerXPGainAnimation(
                        amount: xpResult.amount, activity: .exerciseComplete(exercise.type)
                    )
                }
                // Completion and XP are confirmed. Later optional refresh failures do not need a retry.
                showCompletion = false
                dismiss()
                _ = try? await container.supabaseDataService.incrementEventProgress(activityType: exercise.type.rawValue)
                if let profile = try? await container.supabaseAuthService.fetchProfile(),
                   let milestones = try? await container.supabaseDataService.checkMilestoneTriggers(
                    exerciseCount: profile.stats?.totalExercisesCompleted ?? 0,
                    newLevel: xpResult.leveledUp ? xpResult.newLevel : nil
                   ) {
                    if xpResult.leveledUp {
                        appState.showLevelUpCelebration(level: xpResult.newLevel, title: xpResult.newTitle)
                    }
                    appState.addCelebrations(milestones.map { $0.toCelebrationEvent(userId: profile.id) })
                }
                let achievementService = container.achievementService
                Task.detached(priority: .utility) { _ = try? await achievementService.checkBadgeProgress() }
            } catch {
                completionError = "Your exercise hasn't finished saving. Retry to save this same session and its XP."
                showCompletion = true
            }
        }
    }

}

struct ExerciseCompletionView: View {
    @Binding var rating: Int
    var isSubmitting = false
    var errorMessage: String? = nil
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            Text("Exercise Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("How was this exercise?")
                .font(.headline)

            HStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(star <= rating ? .yellow : SupportTheme.textSecondary)
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            .accessibilityLabel("\(star) stars")
                    }
                }
            }

            .disabled(isSubmitting)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(errorMessage)
            }

            Button {
                onComplete()
            } label: {
                Text(isSubmitting ? "Saving…" : (errorMessage == nil ? "Done" : "Retry Save"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
            .padding(SupportTheme.Spacing.m)
            .disabled(isSubmitting)
        }
        .padding(SupportTheme.Spacing.m)
        .interactiveDismissDisabled(isSubmitting)
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
