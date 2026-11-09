import SwiftUI

/// One-at-a-time questionnaire flow with progress tracking and crisis handling
@MainActor
struct AssessmentFlowView: View {
    let template: AssessmentTemplate
    @ObservedObject var outcomeService: OutcomeTrackingService
    @Binding var isPresented: Bool

    @State private var currentQuestionIndex = 0
    @State private var answers: [String: Int] = [:]
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var showingCrisisAlert = false
    @State private var crisisContext: [String: Int]? = nil
    @State private var submission: OutcomeAssessmentSubmission?
    @State private var submissionError: String?
    @State private var showingSubmissionError = false

    var currentQuestion: AssessmentQuestion? {
        guard currentQuestionIndex < template.questions.count else { return nil }
        return template.questions[currentQuestionIndex]
    }

    var isLastQuestion: Bool {
        currentQuestionIndex == template.questions.count - 1
    }

    var canSubmit: Bool {
        guard let type = AssessmentType(rawValue: template.code) else { return false }
        return (try? type.score(answers: answers, questions: template.questions)) != nil
    }

    var progressPercentage: Double {
        let answered = Double(answers.count)
        let total = Double(template.questions.count)
        return answered / total
    }

    var isPHQ9Q9: Bool {
        template.code == "PHQ9" && (currentQuestion?.id == "9" || currentQuestionIndex == 8)
    }

    var body: some View {
        ZStack {
            // Background
            SupportTheme.canvas
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with progress
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(template.name)
                                .font(.system(.title3, design: .default).weight(.bold))
                                .foregroundColor(SupportTheme.accent)

                            Text("Question \(currentQuestionIndex + 1) of \(template.questions.count)")
                                .font(.system(.caption, design: .default).weight(.regular))
                                .foregroundColor(SupportTheme.textSecondary)
                        }

                        Spacer()

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(.title2))
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }

                    // Progress bar
                    ProgressView(value: progressPercentage)
                        .tint(SupportTheme.accent)
                        .frame(height: 4)
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, x: 0, y: 2)

                // Question content
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        if let question = currentQuestion {
                            // Question text with special styling for PHQ-9 Q9
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                if isPHQ9Q9 {
                                    HStack(spacing: SupportTheme.Spacing.xs) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(.body))
                                            .foregroundColor(SupportTheme.accent)

                                        Text("Important")
                                            .font(.system(.caption, design: .default).weight(.semibold))
                                            .foregroundColor(SupportTheme.accent)
                                    }
                                    .padding(SupportTheme.Spacing.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                            .fill(SupportTheme.accent.opacity(0.1))
                                    )
                                }

                                Text(question.text)
                                    .font(.system(.title3, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)
                                    .lineLimit(nil)
                            }
                            .padding(SupportTheme.Spacing.m)
                            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))

                            // Response options (dynamic count based on question)
                            VStack(spacing: SupportTheme.Spacing.s) {
                                ForEach(0..<question.responseOptions.count, id: \.self) { index in
                                    let optionLabel = question.responseOptions[index]
                                    let isSelected = answers[question.id] == index

                                    Button(action: {
                                        guard submission == nil else { return }
                                        answers[question.id] = index
                                        // Check for crisis after selection
                                        if isPHQ9Q9 && index > 0 {
                                            crisisContext = ["q9_score": index]
                                            showingCrisisAlert = true
                                        }
                                    }) {
                                        HStack(spacing: SupportTheme.Spacing.s) {
                                            Text(optionLabel)
                                                .font(.system(.subheadline, design: .default).weight(.medium))
                                                .foregroundColor(
                                                    isSelected ?
                                                    SupportTheme.accent :
                                                    SupportTheme.accent
                                                )

                                            Spacer()

                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(.title3))
                                                    .foregroundColor(SupportTheme.accent)
                                            }
                                        }
                                        .padding(SupportTheme.Spacing.s)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                                .fill(
                                                    isSelected ?
                                                    SupportTheme.accent.opacity(0.1) :
                                                    SupportTheme.surface
                                                )
                                                .stroke(
                                                    isSelected ?
                                                    SupportTheme.accent :
                                                    SupportTheme.textSecondary.opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                            }
                            .padding(SupportTheme.Spacing.m)
                        }

                        // Optional notes section
                        if isLastQuestion {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                                Text("Additional notes (optional)")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)

                                TextEditor(text: $notes)
                                    .disabled(submission != nil)
                                    .font(.system(.subheadline, design: .default).weight(.regular))
                                    .frame(height: 100)
                                    .padding(SupportTheme.Spacing.xs)
                                    .background(
                                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                            .fill(SupportTheme.surface)
                                            .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .padding(SupportTheme.Spacing.m)
                        }
                    }
                    .padding(.vertical, SupportTheme.Spacing.m)
                }

                // Navigation buttons
                HStack(spacing: SupportTheme.Spacing.s) {
                    if currentQuestionIndex > 0 {
                        Button(action: {
                            currentQuestionIndex -= 1
                        }) {
                            Text("Previous")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .fill(SupportTheme.surface)
                                        .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }

                    if !isLastQuestion {
                        Button(action: {
                            if answers[currentQuestion?.id ?? ""] != nil {
                                currentQuestionIndex += 1
                            }
                        }) {
                            Text("Next")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(answers[currentQuestion?.id ?? ""] != nil ? SupportTheme.onAccent : SupportTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .fill(
                                            answers[currentQuestion?.id ?? ""] != nil ?
                                            SupportTheme.accent :
                                            SupportTheme.textSecondary.opacity(0.3)
                                        )
                                )
                        }
                        .disabled(answers[currentQuestion?.id ?? ""] == nil)
                    } else {
                        Button(action: {
                            Task {
                                await submitAssessment()
                            }
                        }) {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(SupportTheme.Spacing.s)
                            } else {
                                Text("Submit Assessment")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(canSubmit ? SupportTheme.onAccent : SupportTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(SupportTheme.Spacing.s)
                                    .background(
                                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                            .fill(
                                                canSubmit ?
                                                SupportTheme.accent :
                                                SupportTheme.textSecondary.opacity(0.3)
                                            )
                                    )
                            }
                        }
                        .disabled(!canSubmit || isSubmitting)
                    }
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
            }

            // Crisis resources stay available even if saving fails.
            if showingCrisisAlert {
                ZStack {
                    SupportTheme.canvas.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: SupportTheme.Spacing.m) {
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: "heart.fill")
                                .font(.system(.title3))
                                .foregroundColor(SupportTheme.accent)

                            Text("We're here for you")
                                .font(.system(.title3, design: .default).weight(.bold))
                                .foregroundColor(SupportTheme.accent)

                            Spacer()
                        }

                        Text("If you're having thoughts of self-harm, please reach out to someone who can help.")
                            .font(.system(.subheadline, design: .default).weight(.regular))
                            .foregroundColor(SupportTheme.accent)
                            .lineLimit(nil)

                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Button(action: {
                                if let url = URL(string: "tel:988") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("988 Suicide & Crisis Lifeline")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(SupportTheme.Spacing.s)
                                    .background(SupportTheme.accent)
                                    .cornerRadius(SupportTheme.controlRadius)
                            }

                            Button(action: {
                                if let url = URL(string: "sms:741741&body=HOME") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Crisis Text Line (text HOME to 741741)")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(SupportTheme.Spacing.s)
                                    .background(SupportTheme.surface)
                                    .cornerRadius(SupportTheme.controlRadius)
                            }
                        }

                        Button(action: {
                            showingCrisisAlert = false
                        }) {
                            Text("I'm Safe - Continue")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Assessment not saved", isPresented: $showingSubmissionError) {
            Button("Retry") { Task { await submitAssessment() } }
            Button("Support Resources") { showingCrisisAlert = true }
            Button("Stay Here", role: .cancel) {}
        } message: {
            Text(submissionError ?? "Your answers are kept on this screen. Try saving again.")
        }
    }

    private func submitAssessment() async {
        guard !isSubmitting, let type = AssessmentType(rawValue: template.code) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if submission == nil {
                submission = try outcomeService.makeAssessmentSubmission(type: type,
                    answers: answers, notes: notes.isEmpty ? nil : notes)
            }
            guard let submission else { return }
            _ = try await outcomeService.submitAssessment(submission)
            isPresented = false
        } catch {
            submissionError = "Your answers are kept on this screen. Retry to save this assessment. Support resources remain available."
            showingSubmissionError = true
        }
    }

}

#if DEBUG
#Preview {
    AssessmentFlowView(
        template: AssessmentTemplate(
            id: UUID(),
            code: "PHQ9",
            name: "PHQ-9",
            description: "Depression screening",
            questions: [],
            scoringRanges: [],
            recommendedFrequencyDays: 14,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        outcomeService: OutcomeTrackingService(supabase: .mock, authService: SupabaseAuthService()),
        isPresented: .constant(true)
    )
}
#endif
