import SwiftUI

struct MoodCheckInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    var existingMood: MoodEntry?

    @State private var moodScore: Double = 3
    @State private var anxietyScore: Double = 1
    @State private var energyScore: Double = 3
    @State private var note: String = ""
    @State private var showAdvanced = false
    @State private var includesAdvancedDetails = false
    @State private var isSaving = false
    @State private var showActionPlanSheet = false
    @State private var actionPlan: ActionPlan?
    @State private var actionPlanItems: [ActionPlanItem] = []
    @State private var planSize: ActionPlanSize = .quick

    // Mood tutorial state
    @AppStorage("mood_tutorial_completed") private var moodTutorialCompleted = false
    @State private var showMoodTutorial = false

    private let moodEmojis = ["😔", "😕", "😐", "🙂", "😁"]
    private let anxietyLabels = ["Very Low", "Low", "Moderate", "High", "Very High"]
    private let energyLabels = ["Exhausted", "Tired", "Okay", "Energetic", "Very High"]

    /// Maximum characters allowed in mood note (prevents payload attacks)
    private let maxNoteLength = 1000

    /// Safe emoji lookup with bounds checking
    private var currentMoodEmoji: String {
        let index = max(0, min(moodEmojis.count - 1, Int(moodScore) - 1))
        return moodEmojis[index]
    }

    /// Safe anxiety label lookup with bounds checking
    private var currentAnxietyLabel: String {
        let index = max(0, min(anxietyLabels.count - 1, Int(anxietyScore) - 1))
        return anxietyLabels[index]
    }

    /// Safe energy label lookup with bounds checking
    private var currentEnergyLabel: String {
        let index = max(0, min(energyLabels.count - 1, Int(energyScore) - 1))
        return energyLabels[index]
    }

    init(existingMood: MoodEntry? = nil) {
        self.existingMood = existingMood
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: 32) {
                    // Mood slider with emoji
                    VStack(spacing: 16) {
                        Text("How are you feeling?")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(currentMoodEmoji)
                            .font(.system(size: 80))

                        MoodSlider(value: Binding(
                            get: { Int(moodScore) },
                            set: { moodScore = Double($0) }
                        ), label: "How are you feeling?")
                    }

                    // Advanced options toggle
                    Button {
                        withAnimation {
                            showAdvanced.toggle()
                            if showAdvanced { includesAdvancedDetails = true }
                        }
                    } label: {
                        HStack {
                            Text("More details")
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    if showAdvanced {
                        VStack(spacing: 24) {
                            // Anxiety
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Anxiety Level")
                                        .font(.headline)
                                    Spacer()
                                    Text(currentAnxietyLabel)
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $anxietyScore, in: 1...5, step: 1)
                                    .accessibilityLabel("Anxiety level")
                                    .accessibilityValue("\(currentAnxietyLabel), \(Int(anxietyScore)) of 5")
                            }

                            // Energy
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Energy Level")
                                        .font(.headline)
                                    Spacer()
                                    Text(currentEnergyLabel)
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $energyScore, in: 1...5, step: 1)
                                    .accessibilityLabel("Energy level")
                                    .accessibilityValue("\(currentEnergyLabel), \(Int(energyScore)) of 5")
                            }

                            // Note
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes (optional)")
                                    .font(.headline)

                                TextField("What's on your mind?", text: $note, axis: .vertical)
                                    .supportField()
                                    .lineLimit(3...6)
                                    .submitLabel(.done)
                                    .onChange(of: note) { _, newValue in
                                        // Enforce maximum note length
                                        if newValue.count > maxNoteLength {
                                            note = String(newValue.prefix(maxNoteLength))
                                        }
                                    }
                                    .onSubmit {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    }

                                // Character count indicator
                                if note.count > maxNoteLength - 100 {
                                    Text("\(note.count)/\(maxNoteLength)")
                                        .font(.caption2)
                                        .foregroundStyle(note.count >= maxNoteLength ? .red : .secondary)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 32)

                    // Save button
                    Button {
                        saveMood()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Mood")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(isSaving)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .sentryMaskMood()
            .navigationTitle("Mood Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Show tutorial on first mood check-in
                if !moodTutorialCompleted {
                    showMoodTutorial = true
                }

                if let mood = existingMood {
                    // Clamp scores to valid range [1, 5] to prevent array index out of bounds
                    moodScore = Double(max(1, min(5, Int(mood.moodScore))))
                    if let anxiety = mood.anxietyScore {
                        anxietyScore = Double(max(1, min(5, Int(anxiety))))
                        showAdvanced = true
                    }
                    if let energy = mood.energyScore {
                        energyScore = Double(max(1, min(5, Int(energy))))
                        showAdvanced = true
                    }
                    if let existingNote = mood.note {
                        note = existingNote
                        showAdvanced = true
                    }
                    includesAdvancedDetails = showAdvanced
                }
            }
            .fullScreenCover(isPresented: $showMoodTutorial) {
                MoodTutorialFlow(onComplete: {
                    moodTutorialCompleted = true
                    showMoodTutorial = false
                })
                .environmentObject(container)
            }
        }
    }

    private func saveMood() {
        guard !isSaving else { return }
        guard let userID = appState.currentUser?.id else { return }
        let owner = OfflineOwnerProof(userId: userID, epoch: appState.accountEpoch)
        let ownerProof: @Sendable () async -> OfflineOwnerProof? = { @MainActor in
            guard appState.currentUser?.id == userID, container.supabaseAuthService.userId == userID else { return nil }
            return OfflineOwnerProof(userId: userID, epoch: appState.accountEpoch)
        }
        Log.ui.debug("[MoodCheckIn] Saving check-in")
        isSaving = true

        let recordedAt = Date()
        let localDate = existingMood?.localDate ?? OfflineLocalDay.string(for: recordedAt)

        let mood = MoodEntry(
            id: existingMood?.id ?? UUID().uuidString,
            localDate: localDate,
            moodScore: Int(moodScore),
            anxietyScore: includesAdvancedDetails ? Int(anxietyScore) : nil,
            energyScore: includesAdvancedDetails ? Int(energyScore) : nil,
            note: !note.isEmpty ? note : nil,
            source: .manual,
            createdAt: existingMood?.createdAt ?? recordedAt
        )

        Task {
            do {
                let reward = try await AtomicCompletionRPC.saveMood(client: container.supabaseClient,
                    owner: owner, ownerProof: ownerProof, localDate: localDate, moodScore: mood.moodScore,
                    anxietyScore: mood.anxietyScore, energyScore: mood.energyScore, note: mood.note)
                guard let savedMoodID = reward.moodID else { throw OfflineMutationError.malformedReceipt }
                if reward.outcome == "kept_existing" {
                    isSaving = false
                    appState.showError(.apiError("A newer check-in was kept. Your entry is still here. Review it and save again if you want to replace that version."))
                    return
                }

                // Award XP for mood check-in (only for new entries, not edits)
                if reward.xpAwarded > 0 {

                    // Trigger XP gain toast IMMEDIATELY for instant gratification
                    await MainActor.run {
                        guard appState.currentUser?.id == owner.userId, appState.accountEpoch == owner.epoch else { return }
                        container.achievementService.triggerXPGainAnimation(
                            amount: reward.xpAwarded,
                            activity: .moodCheckin
                        )
                    }

                    // Fire-and-forget: badge check and activation record run in background
                    // These are slow operations that shouldn't block the UI
                    let achievementService = container.achievementService
                    let activationService = container.activationService
                    Task.detached(priority: .utility) {
                        guard await ownerProof() == owner else { return }
                        do {
                            _ = try await achievementService.checkBadgeProgress()
                            guard await ownerProof() == owner else { return }
                            try await activationService.recordMoodLog()
                        } catch {
                            Log.data.warning("[MoodCheckIn] Background badge/activation check failed: \(error.localizedDescription)")
                        }
                    }
                }

                await MainActor.run {
                    guard appState.currentUser?.id == owner.userId, appState.accountEpoch == owner.epoch else { return }
                    if reward.outcome != "kept_existing", localDate == OfflineLocalDay.string(for: Date()) {
                        appState.todayMood = MoodEntry(id: savedMoodID.uuidString, localDate: mood.localDate,
                            moodScore: mood.moodScore, anxietyScore: mood.anxietyScore, energyScore: mood.energyScore,
                            note: mood.note, source: .manual, createdAt: mood.createdAt)
                    }
                    DebtSourceChanges.saved(date: localDate)

                    // Show level-up celebration if leveled up
                    if reward.levelUp, let level = reward.newLevel, let title = reward.newTitle {
                        appState.showLevelUpCelebration(level: level, title: title)
                    }

                    Log.ui.info("[MoodCheckIn] Saved successfully")
                    // A disclosure gets a quiet acknowledgement only: no haptic, no particles.
                    appState.celebrateCompletion(String(localized: "Check-in saved"), soft: true)
                    dismiss()
                }
            } catch {
                guard await ownerProof() == owner else { isSaving = false; return }
                // Log detailed error for debugging, show generic message to user
                Log.data.warning("[MoodCheckIn] Check-in save failed")
                await MainActor.run {
                    guard appState.currentUser?.id == owner.userId, appState.accountEpoch == owner.epoch else { return }
                    appState.showError(.apiError("Unable to save mood. Please try again."))
                }
            }

            await MainActor.run {
                isSaving = false
            }
        }
    }
}

#Preview {
    MoodCheckInView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
