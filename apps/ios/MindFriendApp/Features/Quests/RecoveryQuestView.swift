import SwiftUI

/// A gentle return to quest practice.
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
                VStack(spacing: SupportTheme.Spacing.l) {
                    headerSection
                    questContentSection
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(SupportTheme.textPrimary)
                    }
                    completeButton
                }
                .padding(SupportTheme.Spacing.m)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .sheet(isPresented: $showCompletionCelebration) {
                RecoveryCompletionView(restoredStreak: restoredStreak ?? streakToRecover) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.Celebration.gold)

            Text("Recovery quest")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader)

            Text("Take one small step back into your practice.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Quest Content Section

    private var questContentSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text(quest.title ?? "Recovery quest")
                .font(.headline)

            Text(quest.description ?? "A small practice to help you begin again.")
                .foregroundStyle(SupportTheme.textSecondary)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Steps")
                    .font(.subheadline.bold())

                if let instructions = quest.instructions {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, step in
                        Button {
                            if index == currentStep + 1 { currentStep = index }
                        } label: {
                            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                            Image(systemName: index <= currentStep ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(index <= currentStep ? SupportTheme.accent : SupportTheme.textSecondary)

                            Text(step)
                                .foregroundStyle(index <= currentStep ? SupportTheme.textPrimary : SupportTheme.textSecondary)
                        }
                            .frame(maxWidth: .infinity, minHeight: SupportTheme.minimumTarget, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Fallback if no instructions
                    Text("Work through the activities at your own pace.")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            // Estimated time
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(SupportTheme.textSecondary)
                Text("\(quest.estimatedMinutes ?? 10) minutes")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(.top, SupportTheme.Spacing.xs)
        }
        .supportCard()
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button {
            Task { await completeRecovery() }
        } label: {
            if isCompleting {
                ProgressView()
                    .tint(SupportTheme.onAccent)
            } else {
                Text("Complete quest")
                    .font(.headline)
            }
        }
        .buttonStyle(.supportPrimary)
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

/// Acknowledges a completed recovery quest without showing server streak data.
struct RecoveryCompletionView: View {
    let restoredStreak: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
            CelebrationParticles().ignoresSafeArea()
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol("checkmark.seal"), tint: SupportTheme.Celebration.gold, diameter: 112)
                    Text("A fresh start").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Your recovery quest is complete.").font(.title3)
                    Text("You've made time for yourself. Come back when it feels right.")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Button("Continue", action: onDismiss).buttonStyle(.supportPrimary)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textPrimary)
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
        }
        .supportSheet()
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
