import SwiftUI

// MARK: - Program Day View

struct ProgramDayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let enrollment: ProgramEnrollment

    @State private var currentDay: ProgramDay?
    @State private var progress: ProgramDayProgress?
    @State private var completedContent: Set<String> = []
    @State private var reflectionText = ""
    @State private var applyText = ""
    @State private var moodBefore: Int?
    @State private var isLoading = true
    @State private var isCompleting = false
    @State private var showSkipConfirm = false
    @State private var showPauseMenu = false

    var canComplete: Bool {
        guard let day = currentDay else { return false }
        let required = Set(day.completionCriteria.required)
        return required.isSubset(of: completedContent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let day = currentDay {
                    // Day header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Day \(day.dayNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if enrollment.canSkip {
                                Button("Skip Day") {
                                    showSkipConfirm = true
                                }
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }

                        Text(day.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        if let theme = day.theme {
                            Text(theme)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress indicator
                    ProgressRow(
                        completedCount: completedContent.count,
                        totalCount: day.content.count,
                        color: enrollment.program?.category.color ?? .blue
                    )

                    // Content blocks
                    ForEach(day.content) { content in
                        ProgramContentBlock(
                            content: content,
                            isCompleted: completedContent.contains(content.type.rawValue),
                            onComplete: { completeContent(content) },
                            reflectionText: $reflectionText,
                            applyText: $applyText,
                            moodBefore: $moodBefore
                        )
                    }

                    // Complete day button
                    Button {
                        Task { await completeDay() }
                    } label: {
                        if isCompleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Complete Day \(enrollment.currentDay)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!canComplete || isCompleting)

                    // Skip info
                    if enrollment.canSkip {
                        Text("\(enrollment.skipsRemaining) skips remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(enrollment.program?.title ?? "Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await pauseEnrollment() }
                    } label: {
                        Label("Pause Program", systemImage: "pause.circle")
                    }

                    Button(role: .destructive) {
                        showPauseMenu = true
                    } label: {
                        Label("Leave Program", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await loadDay() }
        .alert("Skip this day?", isPresented: $showSkipConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Skip", role: .destructive) {
                Task { await skipDay() }
            }
        } message: {
            Text("You have \(enrollment.skipsRemaining) skips remaining. Skipping won't break your streak but you'll miss this day's content.")
        }
        .alert("Leave Program?", isPresented: $showPauseMenu) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { await abandonEnrollment() }
            }
        } message: {
            Text("Your progress will be saved but you'll need to start over if you return.")
        }
    }

    private func loadDay() async {
        isLoading = true
        defer { isLoading = false }

        do {
            currentDay = try await container.supabaseDataService.getProgramDay(
                programId: enrollment.programId,
                dayNumber: enrollment.currentDay
            )
            progress = try await container.supabaseDataService.getDayProgress(
                enrollmentId: enrollment.id,
                dayNumber: enrollment.currentDay
            )

            // Load existing progress
            if let existing = progress?.contentCompleted {
                completedContent = Set(existing.filter { $0.value }.keys)
            }
            reflectionText = progress?.reflectionResponse ?? ""
            applyText = progress?.applyReport ?? ""
            moodBefore = progress?.moodBefore

            Analytics.shared.track(.programDayStarted, properties: [
                "program_id": enrollment.programId,
                "day_number": enrollment.currentDay
            ])
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func completeContent(_ content: ProgramDayContent) {
        completedContent.insert(content.type.rawValue)
        Task { await saveProgress() }
    }

    private func saveProgress() async {
        guard progress != nil else { return }
        
        do {
            let contentDict = Dictionary(uniqueKeysWithValues:
                completedContent.map { ($0, true) }
            )
            
            try await container.supabaseDataService.saveProgramDayProgress(
                enrollmentId: enrollment.id,
                dayNumber: enrollment.currentDay,
                contentCompleted: contentDict,
                reflectionResponse: reflectionText.isEmpty ? nil : reflectionText,
                applyReport: applyText.isEmpty ? nil : applyText,
                moodBefore: moodBefore
            )
        } catch {
            // Log error but don't interrupt user for background saves
            print("Failed to save progress: \(error)")
        }
    }

    private func completeDay() async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            let contentDict = Dictionary(uniqueKeysWithValues:
                completedContent.map { ($0, true) }
            )

            let result = try await container.supabaseDataService.completeProgramDay(
                enrollmentId: enrollment.id,
                dayNumber: enrollment.currentDay,
                contentCompleted: contentDict,
                reflectionResponse: reflectionText.isEmpty ? nil : reflectionText,
                applyReport: applyText.isEmpty ? nil : applyText,
                moodBefore: moodBefore
            )

            if result.programComplete {
                // Show celebration
                if let certNumber = result.certificateNumber {
                    appState.showCelebration(
                        title: "Program Complete!",
                        subtitle: "Certificate: \(certNumber)",
                        icon: "checkmark.seal.fill"
                    )
                }
            }

            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func skipDay() async {
        do {
            _ = try await container.supabaseDataService.skipProgramDay(
                enrollmentId: enrollment.id,
                dayNumber: enrollment.currentDay
            )
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func pauseEnrollment() async {
        do {
            try await container.supabaseDataService.pauseEnrollment(enrollment.id)
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func abandonEnrollment() async {
        do {
            try await container.supabaseDataService.abandonEnrollment(enrollment.id)
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Progress Row

struct ProgressRow: View {
    let completedCount: Int
    let totalCount: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(completedCount) of \(totalCount) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: totalCount > 0 ? geo.size.width * CGFloat(completedCount) / CGFloat(totalCount) : 0)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Program Content Block

struct ProgramContentBlock: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    let onComplete: () -> Void
    @Binding var reflectionText: String
    @Binding var applyText: String
    @Binding var moodBefore: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: content.type.icon)
                    .foregroundStyle(isCompleted ? .green : .blue)
                    .accessibilityHidden(true)
                Text(content.type.displayName)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Completed")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(content.type.displayName)\(isCompleted ? ", completed" : "")")

            // Content based on type
            switch content.type {
            case .learn:
                LearnContentView(content: content, isCompleted: isCompleted, onComplete: onComplete)

            case .practice:
                PracticeContentView(content: content, isCompleted: isCompleted, onComplete: onComplete)

            case .reflect:
                ReflectContentView(content: content, isCompleted: isCompleted, text: $reflectionText, onComplete: onComplete)

            case .apply:
                ApplyContentView(content: content, isCompleted: isCompleted, text: $applyText, onComplete: onComplete)

            case .checkIn:
                CheckInContentView(content: content, isCompleted: isCompleted, selectedMood: $moodBefore, onComplete: onComplete)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Content Type Views

struct LearnContentView: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = content.title {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            if let body = content.body {
                Text(body)
                    .font(.body)
            }
            if !isCompleted {
                Button("Mark as Read", action: onComplete)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Double tap to mark this content as read")
            }
        }
    }
}

struct PracticeContentView: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let intro = content.intro {
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if content.exerciseId != nil {
                // TODO: Link to exercise view
                Button {
                    onComplete()
                } label: {
                    Label(isCompleted ? "Completed" : "Start Exercise", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCompleted)
                .accessibilityHint(isCompleted ? "Exercise completed" : "Double tap to start the exercise")
            } else if let duration = content.durationMinutes {
                Button {
                    onComplete()
                } label: {
                    Label(isCompleted ? "Completed" : "Practice (\(duration) min)", systemImage: "timer")
                }
                .buttonStyle(.bordered)
                .disabled(isCompleted)
                .accessibilityHint(isCompleted ? "Practice completed" : "Double tap to start \(duration) minute practice")
            }
        }
    }
}

struct ReflectContentView: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    @Binding var text: String
    let onComplete: () -> Void

    private var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = content.prompt {
                Text(prompt)
                    .font(.subheadline)
                    .accessibilityLabel("Reflection prompt: \(prompt)")
            }

            TextEditor(text: $text)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Reflection text entry")
                .accessibilityHint("Enter your reflection here")

            if let minWords = content.minWords {
                Text("\(wordCount)/\(minWords) words")
                    .font(.caption)
                    .foregroundStyle(wordCount >= minWords ? .green : .secondary)
                    .accessibilityLabel("\(wordCount) of \(minWords) words entered\(wordCount >= minWords ? ", minimum reached" : "")")
            }

            if !isCompleted {
                Button("Save Reflection") {
                    onComplete()
                }
                .buttonStyle(.bordered)
                .disabled(content.minWords != nil && wordCount < (content.minWords ?? 0))
                .accessibilityHint(content.minWords != nil && wordCount < (content.minWords ?? 0) ? "Enter at least \(content.minWords ?? 0) words to save" : "Double tap to save your reflection")
            }
        }
    }
}

struct ApplyContentView: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    @Binding var text: String
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let challenge = content.challenge {
                Text(challenge)
                    .font(.subheadline)
                    .accessibilityLabel("Challenge: \(challenge)")
            }

            if content.reportBack == true {
                TextEditor(text: $text)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Report text entry")
                    .accessibilityHint("Share how the challenge went")

                Text("Share how it went")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isCompleted {
                Button("Mark Complete") {
                    onComplete()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Double tap to mark this challenge as complete")
            }
        }
    }
}

struct CheckInContentView: View {
    let content: ProgramDayContent
    let isCompleted: Bool
    @Binding var selectedMood: Int?
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling?")
                .font(.subheadline)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        selectedMood = score
                        if !isCompleted {
                            onComplete()
                        }
                    } label: {
                        Text(moodEmoji(for: score))
                            .font(.title)
                            .opacity(selectedMood == score || isCompleted ? 1 : 0.5)
                    }
                    .accessibilityLabel(moodLabel(for: score))
                    .accessibilityAddTraits(selectedMood == score ? .isSelected : [])
                    .disabled(isCompleted)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mood selection, 1 to 5")
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    private func moodLabel(for score: Int) -> String {
        switch score {
        case 1: return "Very sad, 1 out of 5"
        case 2: return "Sad, 2 out of 5"
        case 3: return "Neutral, 3 out of 5"
        case 4: return "Happy, 4 out of 5"
        case 5: return "Very happy, 5 out of 5"
        default: return "Mood \(score)"
        }
    }
}

#Preview {
    NavigationStack {
        ProgramDayView(enrollment: ProgramEnrollment(
            id: "1",
            userId: "user1",
            programId: "prog1",
            status: .active,
            startedAt: Date(),
            currentDay: 1,
            pausedAt: nil,
            completedAt: nil,
            preferredTimeLocal: "09:00",
            skipsUsed: 0,
            skipsAllowed: 3,
            streakDays: 0,
            longestStreak: 0,
            program: Program(
                id: "prog1",
                slug: "welcome",
                title: "Welcome Journey",
                description: "Get started",
                durationDays: 7,
                category: .intro,
                difficulty: .beginner,
                premiumOnly: false,
                learningObjectives: [],
                tags: [],
                coverImageUrl: nil,
                estimatedDailyMinutes: 10,
                sortOrder: 1,
                methodology: nil,
                evidenceSummary: nil,
                evidenceUrl: nil,
                targetConditions: [],
                requiresBaselineAssessment: false,
                assessmentType: nil
            )
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
