import SwiftUI

/// Full-screen view for participating in a live ritual
struct RitualSessionView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let ritual: CircleRitual
    let isCreator: Bool

    @StateObject private var viewModel: RitualSessionViewModel

    @State private var showReflectionSheet = false
    @State private var showCompletionAlert = false

    init(ritual: CircleRitual, isCreator: Bool) {
        self.ritual = ritual
        self.isCreator = isCreator
        _viewModel = StateObject(wrappedValue: RitualSessionViewModel(ritual: ritual))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [ritual.ritualType.swiftUIColor.opacity(0.3), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ritual.title)
                            .font(.headline)
                        Text(ritual.ritualType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        leaveRitual()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Leave ritual")
                }
                .padding(.horizontal)

                Spacer()

                // Timer ring
                TimerRingView(
                    progress: viewModel.progress,
                    timeRemaining: viewModel.formattedTimeRemaining,
                    color: gradientColor
                )
                .frame(width: 200, height: 200)
                .accessibilityLabel("Timer: \(viewModel.formattedTimeRemaining) remaining")

                // Current prompt
                Text(viewModel.currentPrompt)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Current prompt: \(viewModel.currentPrompt)")

                // Step indicator
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index <= viewModel.currentStepIndex ? gradientColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityLabel("Step \(viewModel.currentStepIndex + 1) of \(viewModel.totalSteps)")

                Spacer()

                // Attendees
                if !viewModel.attendees.isEmpty {
                    VStack(spacing: 8) {
                        Text("\(viewModel.attendees.count) participants")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.attendees) { attendee in
                                    AttendeeAvatarView(displayName: attendee.displayName)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    if isCreator {
                        Button {
                            endRitualForEveryone()
                        } label: {
                            Label("End for Everyone", systemImage: "stop.fill")
                                .font(.subheadline)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        leaveRitual()
                    } label: {
                        Label("Leave", systemImage: "arrow.right.circle")
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.setService(container.ritualService)
            Task {
                await viewModel.startSession()
            }
        }
        .onDisappear {
            viewModel.stopSession()
        }
        .sheet(isPresented: $showReflectionSheet) {
            AddReflectionSheet(ritualId: ritual.id) {
                dismiss()
            }
        }
        .alert("Ritual Complete", isPresented: $showCompletionAlert) {
            Button("Add Reflection") {
                showReflectionSheet = true
            }
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Would you like to share a reflection?")
        }
        .onChange(of: viewModel.isCompleted) { _, completed in
            if completed {
                showCompletionAlert = true
            }
        }
    }

    private var gradientColor: Color {
        switch ritual.ritualType {
        case .gratitude: return .pink
        case .grounding: return .green
        case .wins: return .yellow
        case .breathing: return .blue
        }
    }

    private func leaveRitual() {
        viewModel.stopSession()
        dismiss()
    }

    private func endRitualForEveryone() {
        Task {
            await viewModel.completeRitual()
        }
    }
}

/// ViewModel for managing ritual session state
@MainActor
final class RitualSessionViewModel: ObservableObject {
    private let ritual: CircleRitual
    private var service: RitualService?
    private var timer: Timer?
    private var sessionTask: Task<Void, Never>?
    private var subscriptionTasks: [Task<Void, Never>] = []

    @Published var currentStepIndex: Int = 0
    @Published var currentPrompt: String = ""
    @Published var timeRemaining: Int = 0
    @Published var totalSteps: Int = 0
    @Published var progress: Double = 0
    @Published var attendees: [RitualAttendeeInfo] = []
    @Published var isCompleted = false

    private let promptSequence: RitualPromptSequence

    init(ritual: CircleRitual) {
        self.ritual = ritual
        self.promptSequence = RitualPromptSequence.forType(ritual.ritualType)
        self.totalSteps = promptSequence.steps.count
        self.currentPrompt = promptSequence.steps.first?.prompt ?? ""
        self.timeRemaining = ritual.durationSeconds
    }

    func setService(_ service: RitualService) {
        self.service = service
    }

    func startSession() async {
        guard let service = service else { return }

        do {
            let result = try await service.joinRitual(ritualId: ritual.id)

            // Update from server state
            if let step = result.currentStep {
                self.currentStepIndex = step.stepIndex
                self.currentPrompt = step.prompt
                self.timeRemaining = calculateTotalTimeRemaining()
            }
            self.attendees = result.attendees

            // Subscribe to updates
            await service.subscribeToRitual(
                ritualId: ritual.id,
                onUserJoined: { [weak self] attendee in
                    self?.attendees.append(attendee)
                },
                onUserLeft: { [weak self] userId in
                    self?.attendees.removeAll { $0.userId == userId }
                },
                onCompleted: { [weak self] _, _ in
                    self?.isCompleted = true
                },
                onReflectionAdded: { _ in }
            )

            // Start local timer
            startTimer()
        } catch {
            print("Failed to join ritual: \(error)")
        }
    }

    func stopSession() {
        // Cancel timer
        timer?.invalidate()
        timer = nil

        // Cancel session task
        sessionTask?.cancel()
        sessionTask = nil

        // Cancel all subscription tasks
        for task in subscriptionTasks {
            task.cancel()
        }
        subscriptionTasks.removeAll()

        // Unsubscribe from realtime
        Task {
            await service?.unsubscribeFromRitual()
        }
    }

    deinit {
        timer?.invalidate()
        sessionTask?.cancel()
        for task in subscriptionTasks {
            task.cancel()
        }
    }

    func completeRitual() async {
        guard let service = service else { return }

        do {
            _ = try await service.completeRitual(ritualId: ritual.id)
            isCompleted = true
        } catch {
            print("Failed to complete ritual: \(error)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let elapsed = Int(Date().timeIntervalSince(ritual.scheduledFor))

        // Handle case where ritual hasn't started yet
        if elapsed < 0 {
            progress = 0
            timeRemaining = ritual.durationSeconds - elapsed
            return
        }

        if elapsed >= ritual.durationSeconds {
            isCompleted = true
            timer?.invalidate()
            timer = nil
            return
        }

        // Update progress (clamped to valid range)
        progress = min(1.0, max(0.0, Double(elapsed) / Double(ritual.durationSeconds)))
        timeRemaining = max(0, ritual.durationSeconds - elapsed)

        // Update current step
        if let step = promptSequence.currentStep(elapsedSeconds: elapsed) {
            currentStepIndex = step.stepIndex
            currentPrompt = step.prompt
        }
    }

    private func calculateTotalTimeRemaining() -> Int {
        let elapsed = Int(Date().timeIntervalSince(ritual.scheduledFor))
        return max(0, ritual.durationSeconds - elapsed)
    }

    var formattedTimeRemaining: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Circular timer ring
struct TimerRingView: View {
    let progress: Double
    let timeRemaining: String
    let color: Color

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 12)

            // Progress ring
            Circle()
                .trim(from: 0, to: 1 - progress)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Time display
            VStack(spacing: 4) {
                Text(timeRemaining)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()

                Text("remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Small avatar for attendee
struct AttendeeAvatarView: View {
    let displayName: String

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }
            .accessibilityLabel(displayName)
    }
}

#Preview {
    RitualSessionView(
        ritual: CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Morning Gratitude",
            ritualType: .gratitude,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        ),
        isCreator: true
    )
    .environmentObject(DependencyContainer())
}
