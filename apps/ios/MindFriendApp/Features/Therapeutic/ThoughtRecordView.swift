import SwiftUI

/// CBT Thought Record view implementing the ABC model
/// A = Activating Event (Situation)
/// B = Belief (Automatic Thought)
/// C = Consequence (Emotions)
struct ThoughtRecordView: View {
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
                VStack(spacing: 24) {
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

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Thought Record")
            .navigationBarTitleDisplayMode(.inline)
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
        HStack(spacing: 8) {
            ForEach(ThoughtRecordPhase.allCases, id: \.self) { phase in
                Circle()
                    .fill(phase.rawValue <= viewModel.currentPhase.rawValue ? Color.accentColor : Color(.systemGray4))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Phase 1: Situation

    private var situationPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            phaseHeader(
                title: "What happened?",
                subtitle: "Describe the situation or event that triggered your thoughts."
            )

            TextEditor(text: $viewModel.situation)
                .frame(minHeight: 150)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            promptCard(
                icon: "lightbulb",
                text: "Focus on facts: Where were you? What happened? Who was involved?"
            )
        }
    }

    // MARK: - Phase 2: Automatic Thought

    private var thoughtPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            phaseHeader(
                title: "What thought went through your mind?",
                subtitle: "Capture the automatic thought that appeared."
            )

            TextEditor(text: $viewModel.automaticThought)
                .frame(minHeight: 150)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            promptCard(
                icon: "brain",
                text: "Try to capture the exact thought. What words went through your mind?"
            )
        }
    }

    // MARK: - Phase 3: Emotions

    private var emotionsPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            phaseHeader(
                title: "What emotions did you feel?",
                subtitle: "Select the emotions and rate their intensity."
            )

            // Emotion chips
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(commonEmotions, id: \.self) { emotion in
                    emotionChip(emotion)
                }
            }

            // Selected emotions with intensity
            if !viewModel.selectedEmotions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Intensity")
                        .font(.headline)
                        .padding(.top, 8)

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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func emotionIntensityRow(_ emotion: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(emotion)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(viewModel.selectedEmotions[emotion] ?? 50))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.selectedEmotions[emotion] ?? 50) },
                    set: { viewModel.selectedEmotions[emotion] = Int($0) }
                ),
                in: 0...100,
                step: 5
            )
            .tint(.accentColor)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Phase 4: Evidence

    private var evidencePhase: some View {
        VStack(alignment: .leading, spacing: 20) {
            phaseHeader(
                title: "Examine the evidence",
                subtitle: "What facts support or contradict your thought?"
            )

            // Evidence for
            VStack(alignment: .leading, spacing: 8) {
                Label("Evidence FOR the thought", systemImage: "plus.circle")
                    .font(.headline)
                    .foregroundStyle(.red)

                TextEditor(text: $viewModel.evidenceFor)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color.red.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            }

            // Evidence against
            VStack(alignment: .leading, spacing: 8) {
                Label("Evidence AGAINST the thought", systemImage: "minus.circle")
                    .font(.headline)
                    .foregroundStyle(.green)

                TextEditor(text: $viewModel.evidenceAgainst)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color.green.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 16) {
            phaseHeader(
                title: "Create a balanced thought",
                subtitle: "Write a more realistic alternative thought."
            )

            TextEditor(text: $viewModel.balancedThought)
                .frame(minHeight: 150)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            promptCard(
                icon: "arrow.triangle.2.circlepath",
                text: "What would you tell a friend in this situation? What's a more balanced view?"
            )

            // New emotion intensity
            VStack(alignment: .leading, spacing: 8) {
                Text("How intense are your emotions now?")
                    .font(.headline)

                HStack {
                    Text("0")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: $viewModel.newEmotionIntensity, in: 0...100, step: 5)
                        .tint(.accentColor)

                    Text("100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(viewModel.newEmotionIntensity))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Phase 6: Analysis

    private var analysisPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing your thought record...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let analysis = viewModel.aiAnalysis {
                analysisResultView(analysis)
            } else {
                // Request analysis
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Get AI Insights")
                        .font(.headline)

                    Text("Our AI can help identify thinking patterns and suggest alternative perspectives.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        Task {
                            await viewModel.requestAnalysis()
                        }
                    }) {
                        Label("Analyze Thought Record", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Summary card
            if viewModel.savedRecord != nil {
                summaryCard
            }
        }
    }

    private func analysisResultView(_ analysis: AIThoughtAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Validation
            if let validation = analysis.validationStatement {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Understanding", systemImage: "heart")
                        .font(.headline)
                        .foregroundStyle(.pink)

                    Text(validation)
                        .font(.body)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pink.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Cognitive distortions
            if !analysis.identifiedDistortions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Label("Alternative Perspectives", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(.green)

                    ForEach(analysis.reframingSuggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)

                            Text(suggestion)
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            // Coping strategies
            if !analysis.copingStrategies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Coping Strategies", systemImage: "figure.mind.and.body")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    ForEach(analysis.copingStrategies, id: \.self) { strategy in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)

                            Text(strategy)
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func distortionCard(_ type: CognitiveDistortionType, explanation: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundStyle(.orange)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let explanation = explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(type.reframingTip)
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Great Work!", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            if let improvement = viewModel.emotionImprovement {
                HStack {
                    Text("Emotion intensity reduced by")
                    Text("\(improvement)%")
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
                .font(.subheadline)
            }

            Text("You've completed this thought record. Keep practicing to strengthen your CBT skills.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helper Views

    private func phaseHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func promptCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if viewModel.currentPhase != .situation {
                Button(action: viewModel.previousPhase) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                .tint(.white)
                        } else {
                            Text(viewModel.currentPhase == .reframe ? "Save & Continue" : "Next")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canProceed ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.canProceed || viewModel.isSaving)
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
