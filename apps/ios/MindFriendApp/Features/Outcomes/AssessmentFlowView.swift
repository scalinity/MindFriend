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
    @State private var dismissTrigger = UUID()
    
    var currentQuestion: AssessmentQuestion? {
        guard currentQuestionIndex < template.questions.count else { return nil }
        return template.questions[currentQuestionIndex]
    }
    
    var isLastQuestion: Bool {
        currentQuestionIndex == template.questions.count - 1
    }
    
    var canSubmit: Bool {
        answers.count == template.questions.count
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
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.92, green: 0.96, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with progress
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(size: 18, weight: .bold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            Text("Question \(currentQuestionIndex + 1) of \(template.questions.count)")
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Progress bar
                    ProgressView(value: progressPercentage)
                        .tint(Color(red: 0.2, green: 0.6, blue: 0.4))
                        .frame(height: 4)
                }
                .padding(20)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Question content
                ScrollView {
                    VStack(spacing: 20) {
                        if let question = currentQuestion {
                            // Question text with special styling for PHQ-9 Q9
                            VStack(alignment: .leading, spacing: 12) {
                                if isPHQ9Q9 {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                                        
                                        Text("Important")
                                            .font(.system(size: 12, weight: .semibold, design: .default))
                                            .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.1))
                                    )
                                }
                                
                                Text(question.text)
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                    .lineLimit(nil)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            )
                            
                            // Response options (4 buttons)
                            VStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { index in
                                    let optionLabel = getOptionLabel(for: index, assessmentType: template.code)
                                    let isSelected = answers[question.id] == index
                                    
                                    Button(action: {
                                        answers[question.id] = index
                                        // Check for crisis after selection
                                        if isPHQ9Q9 && index > 0 {
                                            crisisContext = ["q9_score": index]
                                            showingCrisisAlert = true
                                        }
                                    }) {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(optionLabel)
                                                    .font(.system(size: 15, weight: .medium, design: .default))
                                                    .foregroundColor(
                                                        isSelected ?
                                                        Color(red: 0.2, green: 0.6, blue: 0.4) :
                                                        Color(red: 0.1, green: 0.3, blue: 0.5)
                                                    )
                                                
                                                Text("Response \(index)")
                                                    .font(.system(size: 12, weight: .regular, design: .default))
                                                    .foregroundColor(.gray)
                                                    .opacity(0.7)
                                            }
                                            
                                            Spacer()
                                            
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                            }
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(
                                                    isSelected ?
                                                    Color(red: 0.2, green: 0.6, blue: 0.4).opacity(0.1) :
                                                    Color.white
                                                )
                                                .stroke(
                                                    isSelected ?
                                                    Color(red: 0.2, green: 0.6, blue: 0.4) :
                                                    Color.gray.opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                            }
                            .padding(20)
                        }
                        
                        // Optional notes section
                        if isLastQuestion {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Additional notes (optional)")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                
                                TextEditor(text: $notes)
                                    .font(.system(size: 14, weight: .regular, design: .default))
                                    .frame(height: 100)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .padding(20)
                        }
                    }
                    .padding(.vertical, 20)
                }
                
                // Navigation buttons
                HStack(spacing: 12) {
                    if currentQuestionIndex > 0 {
                        Button(action: {
                            currentQuestionIndex -= 1
                        }) {
                            Text("Previous")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            answers[currentQuestion?.id ?? ""] != nil ?
                                            Color(red: 0.2, green: 0.6, blue: 0.4) :
                                            Color.gray.opacity(0.3)
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
                                    .padding(12)
                            } else {
                                Text("Submit Assessment")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(
                                                canSubmit ?
                                                Color(red: 0.2, green: 0.6, blue: 0.4) :
                                                Color.gray.opacity(0.3)
                                            )
                                    )
                            }
                        }
                        .disabled(!canSubmit || isSubmitting)
                    }
                }
                .padding(20)
                .background(Color.white)
            }
            
            // Crisis alert overlay
            if showingCrisisAlert && isPHQ9Q9 {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                            
                            Text("We're here for you")
                                .font(.system(size: 18, weight: .bold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            Spacer()
                        }
                        
                        Text("If you're having thoughts of self-harm, please reach out to someone who can help.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            .lineLimit(nil)
                        
                        VStack(spacing: 10) {
                            Button(action: {}) {
                                Text("988 Suicide & Crisis Lifeline")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color(red: 1.0, green: 0.2, blue: 0.2))
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {}) {
                                Text("Crisis Text Line (text HOME to 741741)")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.8))
                                    .cornerRadius(8)
                            }
                        }
                        
                        Button(action: {
                            showingCrisisAlert = false
                        }) {
                            Text("I'm Safe - Continue")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                    )
                    .padding(20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func getOptionLabel(for index: Int, assessmentType: String) -> String {
        switch assessmentType {
        case "PHQ9", "GAD7":
            let options = ["Not at all", "Several days", "More than half the days", "Nearly every day"]
            return options[safe: index] ?? ""
        case "WHO5":
            let options = ["At no time", "Some of the time", "Less than half the time", "More than half the time", "All of the time"]
            return options[safe: index] ?? ""
        default:
            return "Option \(index + 1)"
        }
    }
    
    private func submitAssessment() async {
        isSubmitting = true
        do {
            let response = try await outcomeService.submitAssessment(
                type: AssessmentType(rawValue: template.code) ?? .phq9,
                answers: answers,
                notes: notes.isEmpty ? nil : notes
            )
            
            isPresented = false
        } catch {
            outcomeService.error = error
        }
        isSubmitting = false
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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
            isActive: true
        ),
        outcomeService: OutcomeTrackingService(supabaseClient: MockSupabaseClient()),
        isPresented: .constant(true)
    )
}
