import SwiftUI

/// Dashboard showing assessment status, recent results, and outcome goals
@MainActor
struct OutcomeHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @ObservedObject var outcomeService: OutcomeTrackingService
    @ObservedObject var authService: SupabaseAuthService
    @StateObject private var insightsService: WellnessInsightsService
    @State private var selectedAssessmentType: AssessmentType?

    // Outcomes tutorial state
    @AppStorage("outcomes_tutorial_completed") private var outcomesTutorialCompleted = false
    @State private var showOutcomesTutorial = false

    init(outcomeService: OutcomeTrackingService, authService: SupabaseAuthService) {
        self.outcomeService = outcomeService
        self.authService = authService
        self._insightsService = StateObject(wrappedValue: WellnessInsightsService(authService: authService))
    }
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
    
    private var hasAnyData: Bool {
        !dueAssessments.isEmpty ||
        !outcomeService.recentResponses.isEmpty ||
        !outcomeService.outcomeGoals.isEmpty
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
                        
                        // Empty state for brand-new users
                        if !hasAnyData {
                            emptyStateSection
                        }
                        
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

                        // Wellness Insights (mood trend + helpful activities)
                        if hasAnyData {
                            WellnessInsightsCard(insightsService: insightsService)
                                .padding(.horizontal, 20)
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
            // Wait for authentication to be ready
            guard authService.userId != nil else {
                print("[OutcomeHomeView] Not authenticated yet, skipping data load")
                return
            }

            do {
                print("[OutcomeHomeView] Loading assessment templates...")
                try await outcomeService.loadAssessmentTemplates()
                print("[OutcomeHomeView] Loaded \(outcomeService.assessmentTemplates.count) templates")

                print("[OutcomeHomeView] Loading assessment schedules...")
                try await outcomeService.loadAssessmentSchedules()
                print("[OutcomeHomeView] Loaded \(outcomeService.assessmentSchedules.count) schedules")

                print("[OutcomeHomeView] Loading outcome goals...")
                try await outcomeService.loadOutcomeGoals()
                print("[OutcomeHomeView] Loaded \(outcomeService.outcomeGoals.count) goals")

                print("[OutcomeHomeView] Loading recent responses...")
                try await outcomeService.loadRecentResponses()
                print("[OutcomeHomeView] Loaded \(outcomeService.recentResponses.count) responses")
            } catch {
                print("[OutcomeHomeView] ERROR: \(error)")
            }
        }
        .onChange(of: authService.userId) { _, newValue in
            guard newValue != nil else { return }
            Task {
                do {
                    try await outcomeService.loadAssessmentTemplates()
                    try await outcomeService.loadAssessmentSchedules()
                    try await outcomeService.loadOutcomeGoals()
                    try await outcomeService.loadRecentResponses()
                } catch {
                    print("[OutcomeHomeView] ERROR reloading on auth change: \(error)")
                }
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            // Only show tutorial when outcomes tab is actually selected
            if newTab == .outcomes && !outcomesTutorialCompleted {
                showOutcomesTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showOutcomesTutorial) {
            OutcomesTutorialFlow(onComplete: {
                outcomesTutorialCompleted = true
                showOutcomesTutorial = false
            })
            .environmentObject(container)
        }
    }
}

// MARK: - Supporting Views

private extension OutcomeHomeView {
    var emptyStateSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start tracking your progress")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                    Text("Take a quick check-in to set a baseline and unlock personalized goals.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button {
                if let template = outcomeService.assessmentTemplates.first,
                   let type = AssessmentType(rawValue: template.code) {
                    selectedAssessmentType = type
                    showingAssessmentFlow = true
                }
            } label: {
                Text("Take your first assessment")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.6, blue: 0.4))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 20)
    }
}

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
    let authService = SupabaseAuthService()
    return OutcomeHomeView(
        outcomeService: OutcomeTrackingService(supabase: .mock, authService: authService),
        authService: authService
    )
}
