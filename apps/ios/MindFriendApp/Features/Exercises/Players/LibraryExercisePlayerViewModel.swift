import SwiftUI
import Combine

/// ViewModel for library exercise players
/// Manages common state and type-specific state for all exercise types
@MainActor
class LibraryExercisePlayerViewModel: ObservableObject {
    // MARK: - Dependencies

    let exercise: Exercise
    private let dataService: SupabaseDataService
    private let efficacyEngine: InterventionEfficacyEngine?
    private let achievementService: AchievementService?

    // MARK: - Common State

    @Published var isPlaying = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var timeRemaining: Int
    @Published var progress: Double = 0
    @Published var showCompletion = false
    @Published var rating: Int = 0

    // Session tracking
    @Published private(set) var session: ExerciseSession?
    @Published var isTrackingEfficacy = false
    @Published var currentTrajectory: [TrajectoryPoint] = []
    @Published var showBreakthroughCelebration = false
    @Published var breakthroughSecond: Int?

    // MARK: - Breathing State

    @Published var breathingPhase: LibraryBreathingPhase = .inhale
    @Published var breathingCircleScale: CGFloat = 0.5
    @Published var currentCycle: Int = 1
    @Published var totalCycles: Int = 8

    // MARK: - Meditation State

    @Published var currentSegmentIndex: Int = 0
    @Published var segments: [MeditationSegment] = []

    // MARK: - Grounding State

    @Published var acknowledgedItems: Set<Int> = []
    @Published var groundingResponses: [String] = []
    @Published var currentGroundingIndex: Int = 0

    // MARK: - Journaling State

    @Published var journalResponses: [String] = []

    // MARK: - Movement State

    @Published var currentMovementIndex: Int = 0
    @Published var movementTimeRemaining: Int = 0

    // MARK: - Audio

    @Published var audioPlayer = StreamingAudioPlayer()
    @Published var hasAudio: Bool = false

    // MARK: - Private

    private var timer: Timer?
    private var breathingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var breathingInstructions: BreathingInstructions? {
        if case .breathing(let instructions) = exercise.instructions {
            return instructions
        }
        return nil
    }

    var meditationInstructions: MeditationInstructions? {
        if case .meditation(let instructions) = exercise.instructions {
            return instructions
        }
        return nil
    }

    var groundingInstructions: GroundingInstructions? {
        if case .grounding(let instructions) = exercise.instructions {
            return instructions
        }
        return nil
    }

    var journalingInstructions: JournalingInstructions? {
        if case .journaling(let instructions) = exercise.instructions {
            return instructions
        }
        return nil
    }

    var movementInstructions: MovementInstructions? {
        if case .movement(let instructions) = exercise.instructions {
            return instructions
        }
        return nil
    }

    var genericSteps: [GenericStep]? {
        if case .generic(let steps) = exercise.instructions {
            return steps
        }
        return nil
    }

    var timeRemainingFormatted: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var breathingPhaseColors: [Color] {
        switch breathingPhase {
        case .inhale:
            return [Color.blue.opacity(0.3), Color.blue.opacity(0.1)]
        case .holdIn, .holdOut:
            return [Color.purple.opacity(0.3), Color.purple.opacity(0.1)]
        case .exhale:
            return [Color.green.opacity(0.3), Color.green.opacity(0.1)]
        }
    }

    // MARK: - Initialization

    init(
        exercise: Exercise,
        dataService: SupabaseDataService,
        efficacyEngine: InterventionEfficacyEngine? = nil,
        achievementService: AchievementService? = nil
    ) {
        self.exercise = exercise
        self.dataService = dataService
        self.efficacyEngine = efficacyEngine
        self.achievementService = achievementService
        self.timeRemaining = exercise.durationSeconds

        setupTypeSpecificState()
        setupEfficacyTracking()
    }

    private func setupTypeSpecificState() {
        // Breathing
        if let breathing = breathingInstructions {
            totalCycles = breathing.cycles
        }

        // Meditation
        if let meditation = meditationInstructions {
            segments = meditation.segments
        }

        // Grounding
        if let grounding = groundingInstructions {
            groundingResponses = Array(repeating: "", count: grounding.prompts.count)
        }

        // Journaling
        if let journaling = journalingInstructions {
            journalResponses = Array(repeating: "", count: journaling.prompts.count)
        }

        // Movement
        if let movement = movementInstructions, let first = movement.movements.first {
            movementTimeRemaining = first.durationSeconds
        }

        // Audio - load if exercise has audio URL
        if let audioUrlString = exercise.audioUrl, let audioUrl = URL(string: audioUrlString) {
            hasAudio = true
            audioPlayer.load(url: audioUrl)
        }
    }

    private func setupEfficacyTracking() {
        guard let engine = efficacyEngine else { return }

        engine.tracker.$currentTrajectory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trajectory in
                self?.currentTrajectory = trajectory
                self?.checkForBreakthrough()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Management

    func startSession() async {
        do {
            let sessionId = try await dataService.startExerciseSession(exerciseId: exercise.id)
            session = ExerciseSession(
                id: sessionId,
                exerciseId: exercise.id,
                startedAt: Date(),
                endedAt: nil,
                completed: false,
                rating: nil,
                note: nil
            )
        } catch {
            print("Failed to start exercise session: \(error)")
        }
    }

    // MARK: - Playback Control

    func startTimer() {
        guard !isPlaying else { return }
        isPlaying = true

        // Start efficacy tracking
        Task {
            await startEfficacyTracking()
        }

        // Start appropriate timer based on exercise type
        switch exercise.type {
        case .breathing:
            startBreathingCycle()
        case .meditation:
            startMeditationTimer()
        case .grounding:
            // Grounding is user-paced, no auto timer
            startBasicTimer()
        case .journaling:
            // Journaling is user-paced, no timer needed
            break
        case .movement:
            startMovementTimer()
        }
    }

    func pauseTimer() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        breathingTask?.cancel()
        breathingTask = nil
    }

    func resetTimer() {
        pauseTimer()
        timeRemaining = exercise.durationSeconds
        elapsedTime = 0
        progress = 0
        currentCycle = 1
        currentSegmentIndex = 0
        currentMovementIndex = 0
        currentGroundingIndex = 0
        acknowledgedItems.removeAll()
        breathingPhase = .inhale
        breathingCircleScale = 0.5

        if let movement = movementInstructions, let first = movement.movements.first {
            movementTimeRemaining = first.durationSeconds
        }

        // Stop efficacy tracking
        Task {
            if isTrackingEfficacy {
                try? await stopEfficacyTracking()
            }
            isTrackingEfficacy = false
            currentTrajectory = []
        }
    }

    func completeExercise() {
        pauseTimer()

        Task {
            await stopEfficacyTracking()
            showCompletion = true
        }
    }

    // MARK: - Breathing

    private func startBreathingCycle() {
        guard let instructions = breathingInstructions else {
            startBasicTimer()
            return
        }

        breathingTask?.cancel()
        breathingTask = Task {
            while currentCycle <= totalCycles && !Task.isCancelled {
                // Inhale
                await setPhase(.inhale, scale: 1.0, duration: instructions.pattern.inhaleSeconds)
                guard !Task.isCancelled else { return }

                // Hold in (if > 0)
                if instructions.pattern.holdInSeconds > 0 {
                    await setPhase(.holdIn, scale: 1.0, duration: instructions.pattern.holdInSeconds)
                    guard !Task.isCancelled else { return }
                }

                // Exhale
                await setPhase(.exhale, scale: 0.5, duration: instructions.pattern.exhaleSeconds)
                guard !Task.isCancelled else { return }

                // Hold out (if > 0)
                if instructions.pattern.holdOutSeconds > 0 {
                    await setPhase(.holdOut, scale: 0.5, duration: instructions.pattern.holdOutSeconds)
                    guard !Task.isCancelled else { return }
                }

                currentCycle += 1
            }

            // Exercise complete
            await MainActor.run {
                completeExercise()
            }
        }
    }

    private func setPhase(_ phase: LibraryBreathingPhase, scale: CGFloat, duration: Double) async {
        await MainActor.run {
            breathingPhase = phase
            HapticManager.selection()
            withAnimation(.easeInOut(duration: duration)) {
                breathingCircleScale = scale
            }
        }

        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        } catch {
            // Task was cancelled
        }
    }

    // MARK: - Meditation

    private func startMeditationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeditation()
            }
        }
    }

    private func updateMeditation() {
        guard timeRemaining > 0 else {
            completeExercise()
            return
        }

        timeRemaining -= 1
        elapsedTime += 1
        progress = elapsedTime / Double(exercise.durationSeconds)

        // Check if we should advance to next segment
        if let meditation = meditationInstructions {
            let nextIndex = currentSegmentIndex + 1
            if nextIndex < meditation.segments.count {
                let nextSegment = meditation.segments[nextIndex]
                if Int(elapsedTime) >= nextSegment.timestampSeconds {
                    currentSegmentIndex = nextIndex
                    HapticManager.selection()
                }
            }
        }
    }

    func advanceSegment() {
        guard let meditation = meditationInstructions else { return }
        if currentSegmentIndex < meditation.segments.count - 1 {
            currentSegmentIndex += 1
            HapticManager.selection()
        }
    }

    func previousSegment() {
        if currentSegmentIndex > 0 {
            currentSegmentIndex -= 1
            HapticManager.selection()
        }
    }

    // MARK: - Grounding

    func acknowledgeGroundingItem(at index: Int) {
        acknowledgedItems.insert(index)
        HapticManager.selection()

        // Auto-advance if all items for current sense are acknowledged
        if let grounding = groundingInstructions {
            if currentGroundingIndex < grounding.prompts.count - 1 {
                currentGroundingIndex += 1
            } else {
                // All prompts completed
                completeExercise()
            }
        }
    }

    func advanceGrounding() {
        guard let grounding = groundingInstructions else { return }
        if currentGroundingIndex < grounding.prompts.count - 1 {
            currentGroundingIndex += 1
            HapticManager.selection()
        } else {
            completeExercise()
        }
    }

    // MARK: - Movement

    private func startMovementTimer() {
        // If no movement instructions, fall back to basic timer
        guard movementInstructions != nil else {
            startBasicTimer()
            return
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMovement()
            }
        }
    }

    private func updateMovement() {
        guard let movement = movementInstructions else { return }

        if movementTimeRemaining > 0 {
            movementTimeRemaining -= 1
            timeRemaining -= 1
            progress = 1.0 - (Double(timeRemaining) / Double(exercise.durationSeconds))
        } else {
            // Move to next step
            if currentMovementIndex < movement.movements.count - 1 {
                currentMovementIndex += 1
                movementTimeRemaining = movement.movements[currentMovementIndex].durationSeconds
                HapticManager.selection()
            } else {
                completeExercise()
            }
        }
    }

    // MARK: - Basic Timer

    private func startBasicTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    self.elapsedTime += 1
                    self.progress = self.elapsedTime / Double(self.exercise.durationSeconds)
                } else {
                    self.completeExercise()
                }
            }
        }
    }

    // MARK: - Efficacy Tracking

    private func startEfficacyTracking() async {
        guard let engine = efficacyEngine, let session = session else { return }

        do {
            // Get user ID from session or use a placeholder
            let exerciseUUID = UUID(uuidString: exercise.id) ?? UUID()
            let sessionUUID = UUID(uuidString: session.id) ?? UUID()
            // Note: userId should come from auth - using placeholder for now
            try await engine.startSession(
                sessionId: sessionUUID,
                exerciseId: exerciseUUID,
                userId: UUID()  // TODO: Get from auth service
            )
            isTrackingEfficacy = true
        } catch {
            print("Failed to start efficacy tracking: \(error)")
        }
    }

    private func stopEfficacyTracking() async {
        guard let engine = efficacyEngine, isTrackingEfficacy else { return }

        do {
            _ = try await engine.endSession()
        } catch {
            print("Failed to stop efficacy tracking: \(error)")
        }
    }

    private func checkForBreakthrough() {
        guard currentTrajectory.count >= 2 else { return }

        let recent = currentTrajectory.suffix(2)
        guard let previous = recent.first, let current = recent.last else { return }

        let change = current.compositeScore - previous.compositeScore
        let duration = current.secondsFromStart - previous.secondsFromStart

        // Breakthrough: >0.4 improvement within 60 seconds
        if change > 0.4 && duration <= 60 && !showBreakthroughCelebration {
            breakthroughSecond = current.secondsFromStart
            showBreakthroughCelebration = true
            HapticManager.celebrationSuccess()
        }
    }

    // MARK: - Completion

    func submitCompletion() async throws {
        guard let session = session else { return }

        // 1. Mark session complete
        try await dataService.completeExerciseSession(
            sessionId: session.id,
            rating: rating > 0 ? rating : nil,
            note: nil
        )

        // 2. Award XP
        let xpResult = try await dataService.awardXP(
            activity: .exerciseComplete(exercise.type)
        )

        // 3. Trigger XP animation
        achievementService?.triggerXPGainAnimation(
            amount: xpResult.amount,
            activity: .exerciseComplete(exercise.type)
        )

        // 4. Check badges in background
        Task.detached(priority: .utility) { [achievementService] in
            _ = try? await achievementService?.checkBadgeProgress()
        }
    }

    // MARK: - Cleanup

    deinit {
        timer?.invalidate()
        breathingTask?.cancel()
    }
}
