import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var exercises: [Exercise] = []
    @State private var skillProgress: [SkillProgress] = []
    @State private var selectedType: ExerciseType?
    @State private var isLoading = true

    var filteredExercises: [Exercise] {
        guard let type = selectedType else { return exercises }
        return exercises.filter { $0.type == type }
    }

    /// Get skill progress for the selected type
    var selectedSkillProgress: SkillProgress? {
        guard let type = selectedType else { return nil }
        return skillProgress.first { $0.skillType == type }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Type filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "All",
                            isSelected: selectedType == nil,
                            action: { selectedType = nil }
                        )

                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            FilterChip(
                                title: type.rawValue.capitalized,
                                icon: type.icon,
                                isSelected: selectedType == type,
                                action: { selectedType = type }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Skill progress indicator (shown when a type is selected)
                if let skill = selectedSkillProgress {
                    SkillIndicatorView(
                        skillType: skill.skillType,
                        level: skill.skillLevel,
                        xp: skill.xp
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if selectedType != nil {
                    // Show starter indicator for types with no progress
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Complete exercises to level up this skill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Exercises
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if filteredExercises.isEmpty {
                    Text("No exercises found")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredExercises) { exercise in
                            NavigationLink {
                                ExercisePlayerView(exercise: exercise)
                            } label: {
                                ExerciseCard(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Exercises")
        .task {
            await loadExercises()
        }
    }

    private func loadExercises() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let exercisesTask = container.supabaseDataService.getExercises()
            async let skillsTask = container.supabaseDataService.getSkillProgress()

            exercises = try await exercisesTask
            skillProgress = try await skillsTask
        } catch {
            print("ExerciseLibraryView loadExercises error: \(error)")
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct ExerciseCard: View {
    let exercise: Exercise

    private var durationMinutes: Int {
        guard exercise.durationSeconds > 0 else { return 0 }
        return exercise.durationSeconds / 60
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: exercise.type.icon)
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(exercise.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(durationMinutes) min", systemImage: "clock")
                    Label(exercise.type.rawValue.capitalized, systemImage: exercise.type.icon)

                    if let basis = exercise.evidenceBasis {
                        EvidenceBadge(
                            basis: basis,
                            isReviewed: exercise.isTherapistReviewed,
                            showInfo: false
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let exercise: Exercise
    @State private var session: ExerciseSession?
    @State private var isPlaying = false
    @State private var timeRemaining: Int
    @State private var timer: Timer?
    @State private var showCompletion = false
    @State private var rating: Int = 0

    init(exercise: Exercise) {
        self.exercise = exercise
        _timeRemaining = State(initialValue: exercise.durationSeconds)
    }

    var progress: Double {
        guard exercise.durationSeconds > 0 else { return 0 }
        return 1.0 - (Double(timeRemaining) / Double(exercise.durationSeconds))
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Timer circle
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack {
                    Text(timeString)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))

                    Text(isPlaying ? "In Progress" : "Ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250)

            // Exercise content
            if let text = exercise.contentText {
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Controls
            HStack(spacing: 32) {
                Button {
                    resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title)
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
                        .font(.system(size: 80))
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    completeExercise()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCompletion) {
            ExerciseCompletionView(rating: $rating) {
                submitCompletion()
            }
        }
        .task {
            await startSession()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    var timeString: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startSession() async {
        do {
            let sessionId = try await container.supabaseDataService.startExerciseSession(exerciseId: exercise.id)
            session = ExerciseSession(id: sessionId, exerciseId: exercise.id, startedAt: Date(), endedAt: nil, completed: false)
        } catch {
            // Session tracking is optional - log for debugging but allow exercise to continue
            #if DEBUG
            print("Failed to start exercise session: \(error.localizedDescription)")
            #endif
        }
    }

    private func startTimer() {
        isPlaying = true
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
    }

    private func completeExercise() {
        pauseTimer()
        showCompletion = true
    }

    private func submitCompletion() {
        guard let session = session else {
            dismiss()
            return
        }

        Task {
            do {
                try await container.supabaseDataService.completeExerciseSession(
                    sessionId: session.id,
                    rating: rating > 0 ? rating : nil,
                    note: nil
                )

                // Award XP for exercise completion
                let xpResult = try await container.supabaseDataService.awardXP(activity: .exerciseComplete(exercise.type))

                // Update event progress for this exercise type
                _ = try? await container.supabaseDataService.incrementEventProgress(activityType: exercise.type.rawValue)

                await MainActor.run {
                    // Show level-up celebration if leveled up
                    if xpResult.leveledUp {
                        appState.showLevelUpCelebration(level: xpResult.newLevel, title: xpResult.newTitle)
                    }
                    dismiss()
                }
            } catch {
                // Completion tracking failure shouldn't block user - log for debugging
                #if DEBUG
                print("Failed to record exercise completion: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

struct ExerciseCompletionView: View {
    @Binding var rating: Int
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Exercise Complete!")
                .font(.title)
                .fontWeight(.bold)

            Text("How was this exercise?")
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

            Spacer()

            Button {
                onComplete()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
