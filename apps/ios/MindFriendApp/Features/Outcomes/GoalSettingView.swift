import SwiftUI

/// Goal creation interface for setting outcome targets based on baseline assessment
@MainActor
struct GoalSettingView: View {
    let response: AssessmentResponse
    let template: AssessmentTemplate
    @ObservedObject var outcomeService: OutcomeTrackingService
    @Binding var isPresented: Bool
    
    @State private var suggestedTargetScore: Int = 0
    @State private var customTargetScore: String = ""
    @State private var targetDate = Date().addingTimeInterval(86400 * 84) // 12 weeks
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var showingConfirmation = false
    
    var baselineScore: Int { response.totalScore }
    var maxScore: Int { AssessmentType(rawValue: template.code)?.maxScore ?? 27 }
    var recommendedTargetScore: Int {
        let reduction = max(1, Int(Double(baselineScore) * 0.25)) // 25% reduction target
        return max(0, baselineScore - reduction)
    }
    
    var selectedTargetScore: Int {
        if let custom = Int(customTargetScore), custom > 0 {
            return custom
        }
        return recommendedTargetScore
    }
    
    var scoreImprovement: Int {
        baselineScore - selectedTargetScore
    }
    
    var scoreImprovementPercentage: Double {
        guard baselineScore > 0 else { return 0 }
        return Double(scoreImprovement) / Double(baselineScore) * 100
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
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set Your Goal")
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                        
                        Text("Based on your baseline score")
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
                .padding(20)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 20) {
                        // Baseline score card
                        VStack(spacing: 12) {
                            HStack {
                                Text("Your Baseline")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Text("\(baselineScore)")
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                    
                                    Text("/ \(maxScore)")
                                        .font(.system(size: 13, weight: .regular, design: .default))
                                        .foregroundColor(.gray)
                                }
                            }

                            Divider()

                            Text(response.severityLevel)
                                .font(.system(size: 13, weight: .semibold, design: .default))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 20)
                        
                        // Target score section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Target Score")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            // Recommended target
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.95, green: 0.7, blue: 0.0))
                                    
                                    Text("Recommended")
                                        .font(.system(size: 12, weight: .semibold, design: .default))
                                        .foregroundColor(Color(red: 0.95, green: 0.7, blue: 0.0))
                                }
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Text("\(recommendedTargetScore)")
                                                .font(.system(size: 20, weight: .bold, design: .default))
                                                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                            
                                            Text("/ \(maxScore)")
                                                .font(.system(size: 14, weight: .regular, design: .default))
                                                .foregroundColor(.gray)
                                        }

                                        Text("\(scoreImprovement) point reduction (~\(Int(scoreImprovementPercentage))%)")
                                            .font(.system(size: 12, weight: .regular, design: .default))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if customTargetScore.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.2, green: 0.6, blue: 0.4).opacity(0.05))
                                    .stroke(
                                        customTargetScore.isEmpty ?
                                        Color(red: 0.2, green: 0.6, blue: 0.4) :
                                        Color.gray.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                            
                            // Custom target
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Or set custom target")
                                        .font(.system(size: 12, weight: .regular, design: .default))
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    TextField(
                                        "Enter score 0-\(maxScore)",
                                        text: $customTargetScore
                                    )
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())

                                    if !customTargetScore.isEmpty,
                                       let score = Int(customTargetScore),
                                       score >= 0, score <= maxScore {
                                        Text("–\(baselineScore - score) pts")
                                            .font(.system(size: 12, weight: .semibold, design: .default))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Target date section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Target Date")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                
                                DatePicker(
                                    "Target Date",
                                    selection: $targetDate,
                                    in: Date()...Date().addingTimeInterval(86400 * 365),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                
                                Spacer()
                                
                                Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 13, weight: .semibold, design: .default))
                                    .foregroundColor(.gray)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Goal summary card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "target")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                
                                Text("Goal Summary")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                
                                Spacer()
                            }
                            
                            VStack(spacing: 8) {
                                GoalSummaryRow(label: "Current", value: "\(baselineScore)", color: Color.gray)
                                GoalSummaryRow(label: "Target", value: "\(selectedTargetScore)", color: Color(red: 0.2, green: 0.6, blue: 0.4))
                                GoalSummaryRow(label: "Timeline", value: "\(daysUntilTarget) days", color: Color(red: 0.1, green: 0.3, blue: 0.5))
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        
                        Spacer()
                            .frame(height: 20)
                    }
                    .padding(.vertical, 20)
                }
                
                // Action buttons
                VStack(spacing: 10) {
                    Button(action: {
                        showingConfirmation = true
                    }) {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else {
                            Text("Save Goal")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.2, green: 0.6, blue: 0.4))
                                )
                        }
                    }
                    .disabled(isSaving)
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Skip for Now")
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
                .padding(20)
                .background(Color.white)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Save Goal", isPresented: $showingConfirmation) {
            Button("Save", action: saveGoal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a goal to reach \(selectedTargetScore) by \(targetDate.formatted(date: .abbreviated, time: .omitted))?")
        }
    }
    
    private var daysUntilTarget: Int {
        Int(targetDate.timeIntervalSince(Date()) / 86400)
    }
    
    private func saveGoal() {
        isSaving = true
        Task {
            defer { isSaving = false }
            
            do {
                // Call OutcomeTrackingService to save the custom goal
                try await outcomeService.createCustomOutcomeGoal(
                    assessmentTemplateId: template.id,
                    baselineScore: baselineScore,
                    targetScore: selectedTargetScore,
                    targetDate: targetDate,
                    notes: notes.isEmpty ? nil : notes
                )
                
                // Close the sheet on success
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                // Handle error - could show alert to user
                print("Failed to save goal: \(error.localizedDescription)")
                await MainActor.run {
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct GoalSummaryRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.gray)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(color)
            }
        }
    }
}

#if DEBUG
#Preview {
    GoalSettingView(
        response: AssessmentResponse(
            id: UUID(),
            userId: UUID(),
            assessmentTemplateId: UUID(),
            answers: ["1": 1, "2": 2],
            totalScore: 20,
            severityLevel: "severe",
            isBaseline: true,
            notes: nil,
            completedAt: Date(),
            createdAt: Date()
        ),
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
