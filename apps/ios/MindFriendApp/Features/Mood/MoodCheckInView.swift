import SwiftUI

struct MoodCheckInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var saveError: String?

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
    private let moodLabels = ["Very Low", "Low", "Okay", "Good", "Great"]
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
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Mood slider with emoji
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Text("How are you feeling?")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .accessibilityAddTraits(.isHeader)

                        Text(currentMoodEmoji)
                            .font(.system(size: 80))

                        moodChoices
                    }
                    .frame(maxWidth: .infinity)
                    .supportCard()

                    // Advanced options toggle
                    Button {
                        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
                            showAdvanced.toggle()
                            if showAdvanced { includesAdvancedDetails = true }
                        }
                    } label: {
                        HStack {
                            Text("More details")
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minHeight: SupportTheme.minimumTarget)

                    if showAdvanced {
                        VStack(spacing: SupportTheme.Spacing.l) {
                            // Anxiety
                            VStack(spacing: SupportTheme.Spacing.xs) {
                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                    Text("Anxiety level")
                                        .font(.headline)
                                    Text(currentAnxietyLabel)
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                                Slider(value: $anxietyScore, in: 1...5, step: 1)
                                    .accessibilityLabel("Anxiety level")
                                    .accessibilityValue("\(currentAnxietyLabel), \(Int(anxietyScore)) of 5")
                            }

                            // Energy
                            VStack(spacing: SupportTheme.Spacing.xs) {
                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                    Text("Energy level")
                                        .font(.headline)
                                    Text(currentEnergyLabel)
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                                Slider(value: $energyScore, in: 1...5, step: 1)
                                    .accessibilityLabel("Energy level")
                                    .accessibilityValue("\(currentEnergyLabel), \(Int(energyScore)) of 5")
                            }

                            // Note
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
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
                                        .foregroundStyle(note.count >= maxNoteLength ? .red : SupportTheme.textSecondary)
                                }
                            }
                        }
                        .supportCard()
                        .transition(.opacity)
                    }

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(SupportTheme.textPrimary)
                    }

                    // Save button
                    Button {
                        saveMood()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(SupportTheme.onAccent)
                        } else {
                            Text("Save Mood")
                        }
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(isSaving)
                }
                .frame(maxWidth: SupportTheme.readableWidth)
                .padding(SupportTheme.Spacing.m)
                .frame(maxWidth: .infinity)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .scrollDismissesKeyboard(.interactively)
            .sentryMaskMood()
            .navigationTitle("Mood check-in")
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

    private var moodChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : (typeSize >= .xxLarge ? 2 : 5)),
                  spacing: SupportTheme.Spacing.xs) {
            ForEach(0..<moodEmojis.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) { moodScore = Double(index + 1) }
                } label: {
                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text(moodEmojis[index]).font(.title2)
                        Text(moodLabels[index]).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: Int(moodScore) == index + 1 ? "checkmark.circle.fill" : "circle")
                            .font(.caption).accessibilityHidden(true)
                    }
                }
                // Five across on a phone: the default 16-point inset leaves too little room for "Great".
                .buttonStyle(SupportSecondaryButtonStyle(horizontalPadding: SupportTheme.Spacing.xs))
                .accessibilityLabel("How are you feeling?, \(moodLabels[index])")
                .accessibilityValue("\(index + 1) of 5")
                .accessibilityAddTraits(Int(moodScore) == index + 1 ? .isSelected : [])
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
        saveError = nil

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
                    saveError = "A newer check-in was kept. Your entry is still here. Review it and save again if you want to replace that version."
                    return
                }

                // Award XP for mood check-in (only for new entries, not edits)
                if reward.xpAwarded > 0 {

                    // Fire-and-forget: badge check and activation record run in background
                    // These are slow operations that shouldn't block the UI
                    let achievementService = container.achievementService
                    let activationService = container.activationService
                    Task.detached(priority: .utility) {
                        guard await ownerProof() == owner else { return }
                        do {
                            _ = try await achievementService.checkBadgeProgress(presentCelebration: false)
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
                    saveError = "Unable to save mood. Please try again."
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
