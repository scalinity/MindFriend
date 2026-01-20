import SwiftUI

/// Dashboard showing assessment status, recent results, and outcome goals
@MainActor
struct OutcomeHomeView: View {
    @ObservedObject var outcomeService: OutcomeTrackingService
    @State private var selectedAssessmentType: AssessmentType?
    @State private var showingAssessmentFlow = false
    @State private var showingResults = false
    @State private var selectedResult: AssessmentResponse?
    @State private var selectedGoal: OutcomeGoal?
    @State private var showingProgressChart = false
    @State private var progressChartAssessments: [AssessmentResponse] = []
    
    var dueAssessments: [AssessmentSchedule] {
        outcomeService.assessmentSchedules
            .filter { $0.isDue && $0.enabled }
            .sorted { $0.nextDueAt < $1.nextDueAt }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.92, green: 0.96, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wellness Tracking")
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            Text("Monitor your mental health journey")
                                .font(.system(size: 16, weight: .regular, design: .default))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Due Assessments
                        if !dueAssessments.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Assessments Due")
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                    .padding(.horizontal, 20)
                                
                                ForEach(dueAssessments, id: \.id) { schedule in
                                    if let template = outcomeService.assessmentTemplates
                                        .first(where: { $0.id == schedule.assessmentTemplateId }) {
                                        
                                        Button(action: {
                                            selectedAssessmentType = AssessmentType(rawValue: template.code)
                                            showingAssessmentFlow = true
                                        }) {
                                            HStack(spacing: 16) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(template.name)
                                                        .font(.system(size: 16, weight: .semibold, design: .default))
                                                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                                    
                                                    Text("Due today")
                                                        .font(.system(size: 13, weight: .regular, design: .default))
                                                        .foregroundColor(.gray)
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                                            }
                                            .padding(16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white)
                                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                            )
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        
                        // Recent Results
                        if !outcomeService.recentResponses.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent Results")
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                    .padding(.horizontal, 20)
                                
                                ForEach(outcomeService.recentResponses.prefix(3), id: \.id) { response in
                                    Button(action: {
                                        selectedResult = response
                                        showingResults = true
                                    }) {
                                        RecentResultCard(response: response)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // Outcome Goals
                        if !outcomeService.outcomeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Goals")
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                    .padding(.horizontal, 20)
                                
                                ForEach(outcomeService.outcomeGoals.filter({ !$0.achieved }), id: \.id) { goal in
                                    Button(action: {
                                        selectedGoal = goal
                                        Task {
                                            do {
                                                progressChartAssessments = try await outcomeService.getAssessmentResponses(
                                                    assessmentTemplateId: goal.assessmentTemplateId
                                                )
                                                showingProgressChart = true
                                            } catch {
                                                print("Error: \(error)")
                                            }
                                        }
                                    }) {
                                        OutcomeGoalCard(goal: goal)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        Spacer()
                            .frame(height: 20)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationDestination(isPresented: $showingAssessmentFlow) {
                if let type = selectedAssessmentType,
                   let template = outcomeService.assessmentTemplates
                    .first(where: { AssessmentType(rawValue: $0.code) == type }) {
                    
                    AssessmentFlowView(
                        template: template,
                        outcomeService: outcomeService,
                        isPresented: $showingAssessmentFlow
                    )
                }
            }
            .navigationDestination(isPresented: $showingResults) {
                if let result = selectedResult,
                   let template = outcomeService.assessmentTemplates
                    .first(where: { $0.id == result.assessmentTemplateId }) {
                    
                    ResultsView(
                        response: result,
                        template: template,
                        outcomeService: outcomeService,
                        isPresented: $showingResults
                    )
                }
            }
            .navigationDestination(isPresented: $showingProgressChart) {
                if let goal = selectedGoal,
                   let template = outcomeService.assessmentTemplates
                    .first(where: { $0.id == goal.assessmentTemplateId }),
                   let assessmentType = AssessmentType(rawValue: template.code) {
                    
                    ProgressChartView(
                        assessmentType: assessmentType,
                        responses: progressChartAssessments,
                        goal: goal
                    )
                }
            }
        }
        .task {
            do {
                try await outcomeService.loadAssessmentTemplates()
                try await outcomeService.loadOutcomeGoals()
            } catch {
                print("Error: \(error)")
            }
        }
    }
}

// MARK: - Supporting Views

struct RecentResultCard: View {
    let response: AssessmentResponse
    
    var severityColor: Color {
        switch response.severityLevel.lowercased() {
        case "minimal": return Color(red: 0.2, green: 0.6, blue: 0.4)
        case "mild": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "moderate": return Color(red: 0.95, green: 0.7, blue: 0.0)
        case "moderately_severe", "moderately severe": return Color(red: 1.0, green: 0.5, blue: 0.0)
        case "severe": return Color(red: 1.0, green: 0.2, blue: 0.2)
        default: return Color.gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Score: \(response.totalScore)")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                
                Text(response.severityLevel)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(severityColor)
                
                Text(response.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct OutcomeGoalCard: View {
    let goal: OutcomeGoal
    
    var progress: Double {
        let range = Double(goal.targetScore - goal.baselineScore)
        guard range != 0 else { return 0 }
        return (Double(goal.targetScore - goal.baselineScore) / range).clamped(to: 0...1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal: \(goal.targetScore) by \(goal.targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                    
                    Text("From baseline: \(goal.baselineScore)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            ProgressView(value: progress)
                .tint(Color(red: 0.2, green: 0.6, blue: 0.4))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.98, green: 0.99, blue: 1.0))
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    OutcomeHomeView(outcomeService: OutcomeTrackingService(supabase: .mock, authService: SupabaseAuthService()))
}
