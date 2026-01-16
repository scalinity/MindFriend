import SwiftUI

/// Full-screen view for completing a recovery quest to restore a broken streak
struct RecoveryQuestView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let streakToRecover: Int
    let attemptId: String
    let quest: StartRecoveryResult.RecoveryQuestInfo

    @State private var currentStep = 0
    @State private var isCompleting = false
    @State private var showCompletionCelebration = false
    @State private var restoredStreak: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    questContentSection
                    completeButton
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showCompletionCelebration) {
                RecoveryCompletionView(restoredStreak: restoredStreak ?? streakToRecover) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Recovery Quest")
                .font(.title2.bold())

            Text("Complete this quest to restore your \(streakToRecover)-day streak")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }

    // MARK: - Quest Content Section

    private var questContentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(quest.title)
                .font(.headline)

            Text(quest.description)
                .foregroundStyle(.secondary)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                Text("Steps")
                    .font(.subheadline.bold())

                if let instructions = quest.instructions {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: index <= currentStep ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(index <= currentStep ? .green : .gray)

                            Text(step)
                                .foregroundStyle(index <= currentStep ? .primary : .secondary)
                        }
                        .onTapGesture {
                            if index == currentStep + 1 {
                                withAnimation { currentStep = index }
                            }
                        }
                    }
                } else {
                    // Fallback if no instructions
                    Text("Complete the quest activities to restore your streak.")
                        .foregroundStyle(.secondary)
                }
            }

            // Estimated time
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("\(quest.estimatedMinutes) minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button {
            Task { await completeRecovery() }
        } label: {
            if isCompleting {
                ProgressView()
                    .tint(.white)
            } else {
                Text("Complete & Restore Streak")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(canComplete ? Color.orange : Color.gray)
        .foregroundStyle(.white)
        .cornerRadius(12)
        .disabled(!canComplete || isCompleting)
    }

    private var canComplete: Bool {
        guard let instructions = quest.instructions else { return true }
        return currentStep >= instructions.count - 1
    }

    // MARK: - Actions

    private func completeRecovery() async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            let result = try await container.supabaseDataService.completeRecoveryQuest(attemptId: attemptId)

            if result.success {
                restoredStreak = result.restoredStreak
                showCompletionCelebration = true

                // Update app state
                await MainActor.run {
                    appState.currentStreak = result.restoredStreak ?? streakToRecover
                }
            } else {
                errorMessage = result.error ?? "Failed to complete recovery quest"
            }
        } catch {
            errorMessage = "Failed to complete recovery: \(error.localizedDescription)"
        }
    }
}

/// Celebration view shown after successfully restoring a streak
struct RecoveryCompletionView: View {
    let restoredStreak: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text("Streak Restored!")
                .font(.largeTitle.bold())

            Text("Your \(restoredStreak)-day streak is back!")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Great job completing the recovery quest. Keep up the momentum!")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    RecoveryQuestView(
        streakToRecover: 14,
        attemptId: "test-attempt",
        quest: StartRecoveryResult.RecoveryQuestInfo(
            id: "test-quest",
            title: "Mindful Breathing",
            description: "Take 10 minutes to practice deep breathing exercises.",
            estimatedMinutes: 10,
            instructions: [
                "Find a quiet, comfortable place to sit",
                "Close your eyes and take 5 deep breaths",
                "Focus on the sensation of your breath",
                "Continue for 10 minutes",
                "Reflect on how you feel"
            ]
        )
    )
}
