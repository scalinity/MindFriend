import SwiftUI
import MindFriendApp

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

    var body: some View {
        NavigationStack {
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
                            }

                            // Note
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes (optional)")
                                    .font(.headline)

                                TextField("What's on your mind?", text: $note, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
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
        Log.ui.debug("[MoodCheckIn] Saving mood, score: \(Int(moodScore)), isUpdate: \(existingMood != nil)")
        isSaving = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: Date())

        let mood = MoodEntry(
            id: existingMood?.id ?? UUID().uuidString,
            localDate: localDate,
            moodScore: Int(moodScore),
            anxietyScore: showAdvanced ? Int(anxietyScore) : nil,
            energyScore: showAdvanced ? Int(energyScore) : nil,
            note: showAdvanced && !note.isEmpty ? note : nil,
            source: .manual,
            createdAt: Date()
        )

        Task {
            do {
                try await container.supabaseDataService.createMood(mood)

                // Award XP for mood check-in (only for new entries, not edits)
                var xpResult: XPAward?
                if existingMood == nil {
                    xpResult = try await container.supabaseDataService.awardXP(activity: .moodCheckin)

                    // Trigger XP gain toast IMMEDIATELY for instant gratification
                    await MainActor.run {
                        container.achievementService.triggerXPGainAnimation(
                            amount: xpResult?.amount ?? 10,
                            activity: .moodCheckin
                        )
                    }

                    // Fire-and-forget: badge check and activation record run in background
                    // These are slow operations that shouldn't block the UI
                    let achievementService = container.achievementService
                    let activationService = container.activationService
                    Task.detached(priority: .utility) {
                        do {
                            _ = try await achievementService.checkBadgeProgress()
                            try await activationService.recordMoodLog()
                        } catch {
                            Log.data.warning("[MoodCheckIn] Background badge/activation check failed: \(error.localizedDescription)")
                        }
                    }
                }

                await MainActor.run {
                    appState.todayMood = mood

                    // Show level-up celebration if leveled up
                    if let result = xpResult, result.leveledUp {
                        appState.showLevelUpCelebration(level: result.newLevel, title: result.newTitle)
                    }

                    Log.ui.info("[MoodCheckIn] Saved successfully")
                    dismiss()
                }
            } catch {
                // Log detailed error for debugging, show generic message to user
                Log.data.error("[MoodCheckIn] Failed to save mood: \(error)")
                await MainActor.run {
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
