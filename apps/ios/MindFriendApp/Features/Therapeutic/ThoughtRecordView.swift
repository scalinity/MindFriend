import SwiftUI

/// CBT Thought Record view implementing the ABC model
/// A = Activating Event (Situation)
/// B = Belief (Automatic Thought)
/// C = Consequence (Emotions)
struct ThoughtRecordView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ThoughtRecordViewModel

    let enrollmentId: String?
    let programDayNumber: Int?
    let onComplete: (TherapeuticThoughtRecord) -> Void

    init(
        enrollmentId: String? = nil,
        programDayNumber: Int? = nil,
        service: TherapeuticProgramService,
        onComplete: @escaping (TherapeuticThoughtRecord) -> Void
    ) {
        self.enrollmentId = enrollmentId
        self.programDayNumber = programDayNumber
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: ThoughtRecordViewModel(
            enrollmentId: enrollmentId,
            programDayNumber: programDayNumber,
            service: service
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Phase indicator
                    phaseIndicator

                    // Current phase content
                    switch viewModel.currentPhase {
                    case .situation:
                        situationPhase
                    case .thought:
                        thoughtPhase
                    case .emotions:
                        emotionsPhase
                    case .evidence:
                        evidencePhase
                    case .reframe:
                        reframePhase
                    case .analysis:
                        analysisPhase
                    }

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .supportScreen()
            .navigationTitle("Thought Record")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                navigationButtons
            }
        }
    }

    // MARK: - Phase Indicator

    private var phaseIndicator: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            ForEach(ThoughtRecordPhase.allCases, id: \.self) { phase in
                Circle()
                    .fill(phase.rawValue <= viewModel.currentPhase.rawValue ? SupportTheme.accent : SupportTheme.separator)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.top, SupportTheme.Spacing.xs)
    }

    // MARK: - Phase 1: Situation

    private var situationPhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            phaseHeader(
                title: "What happened?",
                subtitle: "Describe the situation or event that triggered your thoughts."
            )

            TextEditor(text: $viewModel.situation)
                .frame(minHeight: 150)
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.separator)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .stroke(SupportTheme.separator, lineWidth: 1)
                )

            promptCard(
                icon: "lightbulb",
                text: "Focus on facts: Where were you? What happened? Who was involved?"
            )
        }
    }

    // MARK: - Phase 2: Automatic Thought

    private var thoughtPhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            phaseHeader(
                title: "What thought went through your mind?",
                subtitle: "Capture the automatic thought that appeared."
            )

            TextEditor(text: $viewModel.automaticThought)
                .frame(minHeight: 150)
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.separator)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .stroke(SupportTheme.separator, lineWidth: 1)
                )

            promptCard(
                icon: "brain",
                text: "Try to capture the exact thought. What words went through your mind?"
            )
        }
    }

    // MARK: - Phase 3: Emotions

    private var emotionsPhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            phaseHeader(
                title: "What emotions did you feel?",
                subtitle: "Select the emotions and rate their intensity."
            )

            // Emotion chips
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.s) {
                ForEach(commonEmotions, id: \.self) { emotion in
                    emotionChip(emotion)
                }
            }

            // Selected emotions with intensity
            if !viewModel.selectedEmotions.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Intensity")
                        .font(.headline)
                        .padding(.top, SupportTheme.Spacing.xs)

                    ForEach(Array(viewModel.selectedEmotions.keys.sorted()), id: \.self) { emotion in
                        emotionIntensityRow(emotion)
                    }
                }
            }
        }
    }

    private var commonEmotions: [String] {
        ["Anxious", "Sad", "Angry", "Frustrated", "Guilty", "Ashamed", "Hopeless", "Overwhelmed", "Scared", "Lonely", "Embarrassed", "Jealous"]
    }

    private func emotionChip(_ emotion: String) -> some View {
        let isSelected = viewModel.selectedEmotions[emotion] != nil

        return Button(action: {
            if isSelected {
                viewModel.selectedEmotions.removeValue(forKey: emotion)
            } else {
                viewModel.selectedEmotions[emotion] = 50
            }
        }) {
            Text(emotion)
                .font(.subheadline)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.separator)
                .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func emotionIntensityRow(_ emotion: String) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
            HStack {
                Text(emotion)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(viewModel.selectedEmotions[emotion] ?? 50))%")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.selectedEmotions[emotion] ?? 50) },
                    set: { viewModel.selectedEmotions[emotion] = Int($0) }
                ),
                in: 0...100,
                step: 5
            )
            .tint(SupportTheme.accent)
        }
        .supportCard()
    }

    // MARK: - Phase 4: Evidence

    private var evidencePhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            phaseHeader(
                title: "Examine the evidence",
                subtitle: "What facts support or contradict your thought?"
            )

            // Evidence for
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Label("Evidence FOR the thought", systemImage: "plus.circle")
                    .font(.headline)
                    .foregroundStyle(.red)

                TextEditor(text: $viewModel.evidenceFor)
                    .frame(minHeight: 100)
                    .padding(SupportTheme.Spacing.s)
                    .background(Color.red.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            }

            // Evidence against
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Label("Evidence AGAINST the thought", systemImage: "minus.circle")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.accent)

                TextEditor(text: $viewModel.evidenceAgainst)
                    .frame(minHeight: 100)
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .stroke(SupportTheme.accent.opacity(0.3), lineWidth: 1)
                    )
            }

            promptCard(
                icon: "scale.3d",
                text: "Think of what a fair judge would say. What facts exist on each side?"
            )
        }
    }

    // MARK: - Phase 5: Reframe

    private var reframePhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            phaseHeader(
                title: "Create a balanced thought",
                subtitle: "Write a more realistic alternative thought."
            )

            TextEditor(text: $viewModel.balancedThought)
                .frame(minHeight: 150)
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.separator)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .stroke(SupportTheme.separator, lineWidth: 1)
                )

            promptCard(
                icon: "arrow.triangle.2.circlepath",
                text: "What would you tell a friend in this situation? What's a more balanced view?"
            )

            // New emotion intensity
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("How intense are your emotions now?")
                    .font(.headline)

                HStack {
                    Text("0")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Slider(value: $viewModel.newEmotionIntensity, in: 0...100, step: 5)
                        .tint(SupportTheme.accent)

                    Text("100")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Text("\(Int(viewModel.newEmotionIntensity))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .supportCard()
        }
    }

    // MARK: - Phase 6: Analysis

    private var analysisPhase: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            if viewModel.isAnalyzing {
                VStack(spacing: SupportTheme.Spacing.m) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing your thought record...")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SupportTheme.Spacing.xl)
            } else if let analysis = viewModel.aiAnalysis {
                analysisResultView(analysis)
            } else {
                // Request analysis
                VStack(spacing: SupportTheme.Spacing.m) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("Get AI Insights")
                        .font(.headline)

                    Text("Our AI can help identify thinking patterns and suggest alternative perspectives.")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        Task {
                            await viewModel.requestAnalysis()
                        }
                    }) {
                        Label("Analyze Thought Record", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding(SupportTheme.Spacing.m)
                            .background(SupportTheme.accent)
                            .foregroundStyle(SupportTheme.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                }
                .supportCard()
            }

            // Summary card
            if viewModel.savedRecord != nil {
                summaryCard
            }
        }
    }

    private func analysisResultView(_ analysis: AIThoughtAnalysis) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            // Validation
            if let validation = analysis.validationStatement {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Label("Understanding", systemImage: "heart")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.accent)

                    Text(validation)
                        .font(.body)
                }
                .padding(SupportTheme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }

            // Cognitive distortions
            if !analysis.identifiedDistortions.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Thinking Patterns Identified", systemImage: "brain.head.profile")
                        .font(.headline)

                    ForEach(analysis.identifiedDistortions, id: \.self) { distortion in
                        if let type = CognitiveDistortionType(rawValue: distortion) {
                            distortionCard(type, explanation: analysis.distortionExplanations[distortion])
                        }
                    }
                }
            }

            // Reframing suggestions
            if !analysis.reframingSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Alternative Perspectives", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.accent)

                    ForEach(analysis.reframingSuggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(SupportTheme.accent)

                            Text(suggestion)
                                .font(.subheadline)
                        }
                        .padding(SupportTheme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                }
            }

            // Coping strategies
            if !analysis.copingStrategies.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Coping Strategies", systemImage: "figure.mind.and.body")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.accent)

                    ForEach(analysis.copingStrategies, id: \.self) { strategy in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SupportTheme.accent)

                            Text(strategy)
                                .font(.subheadline)
                        }
                        .padding(SupportTheme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                }
            }
        }
    }

    private func distortionCard(_ type: CognitiveDistortionType, explanation: String?) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundStyle(SupportTheme.accent)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let explanation = explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Text(type.reframingTip)
                .font(.caption)
                .foregroundStyle(SupportTheme.accent)
                .padding(.top, SupportTheme.Spacing.xxs)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Great Work!", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(SupportTheme.accent)

            if let improvement = viewModel.emotionImprovement {
                HStack {
                    Text("Emotion intensity reduced by")
                    Text("\(improvement)%")
                        .fontWeight(.bold)
                        .foregroundStyle(SupportTheme.accent)
                }
                .font(.subheadline)
            }

            Text("You've completed this thought record. Keep practicing to strengthen your CBT skills.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    // MARK: - Helper Views

    private func phaseHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    private func promptCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.accent)

            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            if viewModel.currentPhase != .situation {
                Button(action: viewModel.previousPhase) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
            }

            if viewModel.currentPhase == .analysis {
                Button(action: {
                    if let record = viewModel.savedRecord {
                        onComplete(record)
                        dismiss()
                    }
                }) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .padding(SupportTheme.Spacing.m)
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
            } else {
                Button(action: {
                    Task {
                        await viewModel.nextPhase()
                    }
                }) {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(SupportTheme.accent)
                        } else {
                            Text(viewModel.currentPhase == .reframe ? "Save & Continue" : "Next")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(viewModel.canProceed ? SupportTheme.accent : SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .disabled(!viewModel.canProceed || viewModel.isSaving)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.canvas)
    }
}

// MARK: - Phases

enum ThoughtRecordPhase: Int, CaseIterable {
    case situation = 0
    case thought = 1
    case emotions = 2
    case evidence = 3
    case reframe = 4
    case analysis = 5
}

// MARK: - View Model

@MainActor
final class ThoughtRecordViewModel: ObservableObject {
    @Published var currentPhase: ThoughtRecordPhase = .situation

    // Phase inputs
    @Published var situation = ""
    @Published var automaticThought = ""
    @Published var selectedEmotions: [String: Int] = [:]
    @Published var evidenceFor = ""
    @Published var evidenceAgainst = ""
    @Published var balancedThought = ""
    @Published var newEmotionIntensity: Double = 50

    // State
    @Published var isSaving = false
    @Published var isAnalyzing = false
    @Published var savedRecord: TherapeuticThoughtRecord?
    @Published var aiAnalysis: AIThoughtAnalysis?

    let enrollmentId: String?
    let programDayNumber: Int?
    private let service: TherapeuticProgramService

    init(
        enrollmentId: String?,
        programDayNumber: Int?,
        service: TherapeuticProgramService
    ) {
        self.enrollmentId = enrollmentId
        self.programDayNumber = programDayNumber
        self.service = service
    }

    var canProceed: Bool {
        switch currentPhase {
        case .situation:
            return situation.count >= 10
        case .thought:
            return automaticThought.count >= 10
        case .emotions:
            return !selectedEmotions.isEmpty
        case .evidence:
            return evidenceFor.count >= 5 || evidenceAgainst.count >= 5
        case .reframe:
            return balancedThought.count >= 10
        case .analysis:
            return true
        }
    }

    var emotionImprovement: Int? {
        guard let primary = selectedEmotions.max(by: { $0.value < $1.value }) else { return nil }
        return primary.value - Int(newEmotionIntensity)
    }

    func nextPhase() async {
        guard canProceed else { return }

        // Save after emotions phase (creates the record)
        if currentPhase == .emotions && savedRecord == nil {
            await createRecord()
        }

        // Update after reframe phase
        if currentPhase == .reframe {
            await updateRecord()
        }

        if currentPhase.rawValue < ThoughtRecordPhase.analysis.rawValue {
            currentPhase = ThoughtRecordPhase(rawValue: currentPhase.rawValue + 1) ?? .analysis
        }
    }

    func previousPhase() {
        if currentPhase.rawValue > 0 {
            currentPhase = ThoughtRecordPhase(rawValue: currentPhase.rawValue - 1) ?? .situation
        }
    }

    private func createRecord() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let emotions = selectedEmotions.map { EmotionEntry(emotion: $0.key, intensity: $0.value) }

            savedRecord = try await service.createThoughtRecord(
                situation: situation,
                automaticThought: automaticThought,
                emotions: emotions,
                enrollmentId: enrollmentId,
                programDayNumber: programDayNumber
            )
        } catch {
            print("Failed to create thought record: \(error)")
        }
    }

    private func updateRecord() async {
        guard let recordId = savedRecord?.id else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            savedRecord = try await service.updateThoughtRecord(
                id: recordId,
                evidenceFor: evidenceFor,
                evidenceAgainst: evidenceAgainst,
                balancedThought: balancedThought,
                newEmotionIntensity: Int(newEmotionIntensity)
            )
        } catch {
            print("Failed to update thought record: \(error)")
        }
    }

    func requestAnalysis() async {
        guard let recordId = savedRecord?.id else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            aiAnalysis = try await service.requestThoughtAnalysis(thoughtRecordId: recordId)
        } catch {
            print("Failed to get analysis: \(error)")
        }
    }
}

#Preview {
    Text("Thought Record Preview")
}
