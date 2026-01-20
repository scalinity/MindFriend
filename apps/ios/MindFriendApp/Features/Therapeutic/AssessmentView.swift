import SwiftUI

/// View for completing clinical assessments (PHQ-9 or GAD-7)
struct AssessmentView: View {
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
                .animation(.easeInOut, value: viewModel.currentQuestionIndex)

                // Navigation buttons
                navigationButtons
            }
            .navigationTitle(assessmentType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
                    .animation(.spring(), value: viewModel.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Question View

    private func questionView(index: Int) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question number
                Text("Question \(index + 1) of \(viewModel.questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)

                // Question text
                Text(viewModel.questions[index])
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Time frame reminder
                Text("Over the last 2 weeks, how often have you been bothered by this problem?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Response options
                VStack(spacing: 12) {
                    ForEach(AssessmentResponseOption.allCases, id: \.rawValue) { option in
                        responseButton(option: option, questionIndex: index)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Spacer(minLength: 100)
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
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Previous button
            if viewModel.currentQuestionIndex > 0 {
                Button(action: viewModel.previousQuestion) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .padding()
                    .background(viewModel.canProceed ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                .tint(.white)
                        } else {
                            Text("Submit")
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isComplete ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.isComplete || viewModel.isSubmitting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
        VStack(spacing: 24) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(severity.color.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: Double(result.totalScore) / Double(assessmentType.maxScore))
                    .stroke(severity.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("\(result.totalScore)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text("of \(assessmentType.maxScore)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .padding(.top, 32)

            // Severity label
            HStack {
                Image(systemName: severity.icon)
                Text(severity.displayName)
            }
            .font(.headline)
            .foregroundStyle(severity.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(severity.color.opacity(0.1))
            .clipShape(Capsule())

            // Interpretation
            Text(interpretationText)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()

            // Done button
            Button(action: onDismiss) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
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
