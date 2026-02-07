import SwiftUI

/// Router view that dispatches to type-specific exercise players
struct LibraryExercisePlayerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let exercise: Exercise
    @StateObject private var viewModel: LibraryExercisePlayerViewModel

    @State private var wasPlayingBeforeBackground = false

    init(exercise: Exercise, container: DependencyContainer) {
        self.exercise = exercise
        _viewModel = StateObject(wrappedValue: LibraryExercisePlayerViewModel(
            exercise: exercise,
            dataService: container.supabaseDataService,
            efficacyEngine: container.interventionEfficacyEngine,
            achievementService: container.achievementService
        ))
    }

    var body: some View {
        ZStack {
            // Type-specific player content
            playerContent
        }
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showCompletion) {
            ExerciseCompletionView(rating: $viewModel.rating) {
                submitCompletion()
            }
        }
        .fullScreenCover(isPresented: $viewModel.showBreakthroughCelebration) {
            BreakthroughCelebrationView(breakthroughSecond: viewModel.breakthroughSecond) {
                viewModel.showBreakthroughCelebration = false
            }
        }
        .task {
            await viewModel.startSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onDisappear {
            viewModel.pauseTimer()
        }
    }

    // MARK: - Player Content

    @ViewBuilder
    private var playerContent: some View {
        switch exercise.type {
        case .breathing:
            LibraryBreathingPlayerView(viewModel: viewModel)
        case .meditation:
            LibraryMeditationPlayerView(viewModel: viewModel)
        case .grounding:
            LibraryGroundingPlayerView(viewModel: viewModel)
        case .journaling:
            LibraryJournalingPlayerView(viewModel: viewModel)
        case .movement:
            LibraryMovementPlayerView(viewModel: viewModel)
        }
    }

    // MARK: - Background Handling

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            if viewModel.isPlaying {
                wasPlayingBeforeBackground = true
                viewModel.pauseTimer()
            }
        case .active:
            // Don't auto-resume - let user control
            break
        @unknown default:
            break
        }
    }

    // MARK: - Completion

    private func submitCompletion() {
        Task {
            do {
                try await viewModel.submitCompletion()

                // Check for level up
                let profile = try await container.supabaseAuthService.fetchProfile()
                let celebrations = try await container.supabaseDataService.checkMilestoneTriggers(
                    exerciseCount: profile.stats?.totalExercisesCompleted ?? 0,
                    newLevel: nil
                )

                await MainActor.run {
                    if !celebrations.isEmpty {
                        let events = celebrations.map { $0.toCelebrationEvent(userId: profile.id) }
                        appState.addCelebrations(events)
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
