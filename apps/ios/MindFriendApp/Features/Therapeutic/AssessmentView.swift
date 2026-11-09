import SwiftUI

/// View for completing clinical assessments (PHQ-9 or GAD-7)
struct AssessmentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AssessmentViewModel

    let assessmentType: AssessmentType
    let enrollmentId: String?
    let assessmentPoint: AssessmentPoint
    let onComplete: (AssessmentSubmissionResult) -> Void

    init(
        assessmentType: AssessmentType,
        enrollmentId: String? = nil,
        assessmentPoint: AssessmentPoint = .standalone,
        service: TherapeuticProgramService,
        crisisCoordinator: CrisisInterventionCoordinator,
        onComplete: @escaping (AssessmentSubmissionResult) -> Void
    ) {
        self.assessmentType = assessmentType
        self.enrollmentId = enrollmentId
        self.assessmentPoint = assessmentPoint
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: AssessmentViewModel(
            assessmentType: assessmentType,
            enrollmentId: enrollmentId,
            assessmentPoint: assessmentPoint,
            service: service,
            crisisCoordinator: crisisCoordinator
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Questions
                TabView(selection: $viewModel.currentQuestionIndex) {
                    ForEach(0..<viewModel.questions.count, id: \.self) { index in
                        questionView(index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut, value: viewModel.currentQuestionIndex)

                // Navigation buttons
                navigationButtons
            }
            .supportScreen()
            .navigationTitle(assessmentType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.showError {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text(viewModel.errorMessage ?? "An error occurred")

                        Button("OK", role: .cancel) { viewModel.showError = false }
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(SupportTheme.separator)
                    .frame(height: 4)

                Rectangle()
                    .fill(SupportTheme.accent)
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
                    .animation(reduceMotion ? nil : .spring(), value: viewModel.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Question View

    private func questionView(index: Int) -> some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Question number
                Text("Question \(index + 1) of \(viewModel.questions.count)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.top, SupportTheme.Spacing.l)

                // Question text
                Text(viewModel.questions[index])
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Time frame reminder
                Text("Over the last 2 weeks, how often have you been bothered by this problem?")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Response options
                VStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(AssessmentResponseOption.allCases, id: \.rawValue) { option in
                        responseButton(option: option, questionIndex: index)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.m)

                Spacer(minLength: SupportTheme.Spacing.xl)
            }
        }
    }

    private func responseButton(option: AssessmentResponseOption, questionIndex: Int) -> some View {
        let isSelected = viewModel.responses[questionIndex] == option.rawValue

        return Button(action: {
            viewModel.selectResponse(questionIndex: questionIndex, response: option.rawValue)
        }) {
            HStack {
                Text(option.displayText)
                    .font(.body)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SupportTheme.textPrimary)
                }
            }
            .padding(SupportTheme.Spacing.m)
            .background(isSelected ? SupportTheme.accent : SupportTheme.separator)
            .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            // Previous button
            if viewModel.currentQuestionIndex > 0 {
                Button(action: viewModel.previousQuestion) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
            }

            // Next/Submit button
            if viewModel.currentQuestionIndex < viewModel.questions.count - 1 {
                Button(action: viewModel.nextQuestion) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(viewModel.canProceed ? SupportTheme.accent : SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .disabled(!viewModel.canProceed)
            } else {
                Button(action: {
                    Task {
                        if let result = await viewModel.submitAssessment() {
                            onComplete(result)
                            if !result.requiresCrisisIntervention {
                                dismiss()
                            }
                        }
                    }
                }) {
                    HStack {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(SupportTheme.accent)
                        } else {
                            Text("Submit")
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(viewModel.isComplete ? SupportTheme.accent : SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .disabled(!viewModel.isComplete || viewModel.isSubmitting)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.canvas)
    }
}

// MARK: - View Model

@MainActor
final class AssessmentViewModel: ObservableObject {
    @Published var currentQuestionIndex = 0
    @Published var responses: [Int?]
    @Published var isSubmitting = false
    @Published var showError = false
    @Published var errorMessage: String?

    let assessmentType: AssessmentType
    let enrollmentId: String?
    let assessmentPoint: AssessmentPoint
    let questions: [String]

    private let service: TherapeuticProgramService
    private let crisisCoordinator: CrisisInterventionCoordinator

    init(
        assessmentType: AssessmentType,
        enrollmentId: String?,
        assessmentPoint: AssessmentPoint,
        service: TherapeuticProgramService,
        crisisCoordinator: CrisisInterventionCoordinator
    ) {
        self.assessmentType = assessmentType
        self.enrollmentId = enrollmentId
        self.assessmentPoint = assessmentPoint
        self.service = service
        self.crisisCoordinator = crisisCoordinator

        // Initialize questions based on type
        switch assessmentType {
        case .phq9:
            self.questions = PHQ9Question.allCases.map { $0.questionText }
        case .gad7:
            self.questions = GAD7Question.allCases.map { $0.questionText }
        case .who5, .pss10, .wemwbs:
            // TODO: Add question templates for WHO-5, PSS-10, and WEMWBS
            self.questions = []
        }

        self.responses = Array(repeating: nil, count: self.questions.count)
    }

    var progress: Double {
        let answered = responses.compactMap { $0 }.count
        return Double(answered) / Double(questions.count)
    }

    var canProceed: Bool {
        responses[currentQuestionIndex] != nil
    }

    var isComplete: Bool {
        responses.allSatisfy { $0 != nil }
    }

    func selectResponse(questionIndex: Int, response: Int) {
        responses[questionIndex] = response
    }

    func nextQuestion() {
        guard currentQuestionIndex < questions.count - 1 else { return }
        currentQuestionIndex += 1
    }

    func previousQuestion() {
        guard currentQuestionIndex > 0 else { return }
        currentQuestionIndex -= 1
    }

    func submitAssessment() async -> AssessmentSubmissionResult? {
        guard isComplete else { return nil }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let responseValues = responses.compactMap { $0 }
            let result = try await service.submitAssessment(
                type: assessmentType,
                responses: responseValues,
                enrollmentId: enrollmentId,
                assessmentPoint: assessmentPoint
            )

            // Check if crisis intervention is needed
            if result.requiresCrisisIntervention {
                crisisCoordinator.triggerCrisisIntervention(
                    crisisEventId: result.crisisEventId,
                    onDismiss: {}
                )
            }

            return result
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return nil
        }
    }
}

// MARK: - Assessment Result View

struct AssessmentResultView: View {
    let result: AssessmentSubmissionResult
    let assessmentType: AssessmentType
    let onDismiss: () -> Void

    private var severity: AssessmentSeverity {
        AssessmentSeverity(rawValue: result.severity) ?? .minimal
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(SupportTheme.accent.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: Double(result.totalScore) / Double(assessmentType.maxScore))
                    .stroke(SupportTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("\(result.totalScore)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))

                    Text("of \(assessmentType.maxScore)")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .frame(width: 160, height: 160)
            .padding(.top, SupportTheme.Spacing.xl)

            // Severity label
            HStack {
                Image(systemName: severity.icon)
                Text(severity.displayName)
            }
            .font(.headline)
            .foregroundStyle(SupportTheme.accent)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(SupportTheme.accent.opacity(0.1))
            .clipShape(Capsule())

            // Interpretation
            Text(interpretationText)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textSecondary)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()

            // Done button
            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .padding(SupportTheme.Spacing.m)
        }
    }

    private var interpretationText: String {
        switch assessmentType {
        case .phq9:
            switch severity {
            case .minimal:
                return "Your responses suggest minimal symptoms of depression. Keep maintaining your well-being practices."
            case .mild:
                return "Your responses suggest mild symptoms. The program exercises can help you build coping skills."
            case .moderate:
                return "Your responses suggest moderate symptoms. Consider discussing with a mental health professional."
            case .moderatelySevere, .severe:
                return "Your responses suggest significant symptoms. We recommend speaking with a mental health professional."
            }
        case .gad7:
            switch severity {
            case .minimal:
                return "Your responses suggest minimal anxiety. Keep up your healthy habits."
            case .mild:
                return "Your responses suggest mild anxiety. The exercises in this program can help."
            case .moderate:
                return "Your responses suggest moderate anxiety. Consider consulting a mental health professional."
            case .moderatelySevere, .severe:
                return "Your responses suggest significant anxiety. We recommend professional support."
            }
        case .who5, .pss10, .wemwbs:
            return "Your assessment has been recorded. Continue tracking your progress."
        }
    }
}

#Preview("PHQ-9 Assessment") {
    Text("Assessment Preview")
}
