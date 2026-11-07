import SwiftUI

/// Router view that dispatches to type-specific exercise players
struct LibraryExercisePlayerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let exercise: Exercise
    var onCompleted: ((String) -> Void)? = nil
    @StateObject private var viewModel: LibraryExercisePlayerViewModel

    @State private var wasPlayingBeforeBackground = false

    init(exercise: Exercise, container: DependencyContainer, onCompleted: ((String) -> Void)? = nil) {
        self.exercise = exercise
        self.onCompleted = onCompleted
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
            ExerciseCompletionView(
                rating: $viewModel.rating,
                isSubmitting: viewModel.isSubmittingCompletion,
                errorMessage: viewModel.completionError
            ) {
                submitCompletion()
            }
            .safeAreaInset(edge: .bottom) {
                Text("Efficacy unavailable: no emotional measurements were recorded. You can still save your exercise.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
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
        guard !viewModel.isSubmittingCompletion else { return }
        Task {
            do {
                let sessionId = try await viewModel.submitCompletion()
                // The program callback is emitted only after completion AND XP are confirmed.
                onCompleted?(sessionId)
                viewModel.showCompletion = false
                dismiss()

                // Optional celebrations must not turn a saved exercise into a retry.
                if let profile = try? await container.supabaseAuthService.fetchProfile(),
                   let celebrations = try? await container.supabaseDataService.checkMilestoneTriggers(
                    exerciseCount: profile.stats?.totalExercisesCompleted ?? 0, newLevel: nil
                   ), !celebrations.isEmpty {
                    appState.addCelebrations(celebrations.map { $0.toCelebrationEvent(userId: profile.id) })
                }
            } catch {
                // Keep the model, UUID, rating, and completion sheet available for Retry Save.
                viewModel.showCompletion = true
            }
        }
    }

}

// MARK: - Preview

// Preview removed - requires full DI setup
