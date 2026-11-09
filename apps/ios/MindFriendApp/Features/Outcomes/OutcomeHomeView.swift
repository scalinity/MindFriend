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
    @State private var loadError: String?

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

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ZStack {
                // Gradient background
                SupportTheme.canvas
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.l) {
                        // Header
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text(SupportDestination.outcomes.title)
                                .font(.system(.title, design: .default).weight(.bold))
                                .foregroundColor(SupportTheme.accent)

                            Text("Monitor your mental health journey")
                                .font(.system(.body, design: .default).weight(.regular))
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SupportTheme.Spacing.m)
                        .padding(.top, SupportTheme.Spacing.s)

                        if let loadError {
                            SupportUnavailableState(title: "Assessments unavailable", message: loadError)
                                .padding(.horizontal, SupportTheme.Spacing.m)
                        }

                        // Empty state for brand-new users
                        if !hasAnyData {
                            emptyStateSection
                        }

                        // Due Assessments
                        if !dueAssessments.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Text("Assessments Due")
                                    .font(.system(.body, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)
                                    .padding(.horizontal, SupportTheme.Spacing.m)

                                ForEach(dueAssessments, id: \.id) { schedule in
                                    if let template = outcomeService.assessmentTemplates
                                        .first(where: { $0.id == schedule.assessmentTemplateId }) {

                                        Button(action: {
                                            selectedAssessmentType = AssessmentType(rawValue: template.code)
                                            showingAssessmentFlow = true
                                        }) {
                                            HStack(spacing: SupportTheme.Spacing.m) {
                                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                                    Text(template.name)
                                                        .font(.system(.body, design: .default).weight(.semibold))
                                                        .foregroundColor(SupportTheme.accent)

                                                    Text("Due today")
                                                        .font(.system(.caption, design: .default).weight(.regular))
                                                        .foregroundColor(SupportTheme.textSecondary)
                                                }

                                                Spacer()

                                                Image(systemName: "arrow.right")
                                                    .font(.system(.subheadline).weight(.semibold))
                                                    .foregroundColor(SupportTheme.accent)
                                            }
                                            .padding(SupportTheme.Spacing.m)
                                            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                                        }
                                        .padding(.horizontal, SupportTheme.Spacing.m)
                                    }
                                }
                            }
                        }

                        // Wellness Insights (mood trend + helpful activities)
                        if hasAnyData {
                            WellnessInsightsCard(insightsService: insightsService)
                                .padding(.horizontal, SupportTheme.Spacing.m)
                        }

                        // Recent Results
                        if !outcomeService.recentResponses.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Text("Recent Results")
                                    .font(.system(.body, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)
                                    .padding(.horizontal, SupportTheme.Spacing.m)

                                ForEach(outcomeService.recentResponses.prefix(3), id: \.id) { response in
                                    Button(action: {
                                        selectedResult = response
                                        showingResults = true
                                    }) {
                                        RecentResultCard(response: response)
                                    }
                                    .padding(.horizontal, SupportTheme.Spacing.m)
                                }
                            }
                        }

                        // Outcome Goals
                        if !outcomeService.outcomeGoals.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Text("Your Goals")
                                    .font(.system(.body, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)
                                    .padding(.horizontal, SupportTheme.Spacing.m)

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
                                        OutcomeGoalCard(goal: goal,
                                            assessmentType: outcomeService.assessmentTemplates.first { $0.id == goal.assessmentTemplateId }
                                                .flatMap { AssessmentType(rawValue: $0.code) },
                                            currentScore: outcomeService.recentResponses
                                                .filter { $0.assessmentTemplateId == goal.assessmentTemplateId }
                                                .sorted { $0.completedAt > $1.completedAt }.first?.availableScore)
                                    }
                                    .padding(.horizontal, SupportTheme.Spacing.m)
                                }
                            }
                        }

                        Spacer()
                            .frame(height: 20)
                    }
                    .padding(.vertical, SupportTheme.Spacing.s)
                }
            }
            .supportScreen()
            .navigationTitle(SupportDestination.outcomes.title)
            .navigationBarTitleDisplayMode(.inline)
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
                loadError = error.localizedDescription
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
                    loadError = error.localizedDescription
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
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(SupportTheme.surface.opacity(0.9))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(.title3).weight(.semibold))
                        .foregroundColor(SupportTheme.accent)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Start tracking your progress")
                        .font(.system(.body, design: .default).weight(.semibold))
                        .foregroundColor(SupportTheme.accent)

                    Text("Take a quick check-in to set a baseline and unlock personalized goals.")
                        .font(.system(.subheadline, design: .default).weight(.regular))
                        .foregroundColor(SupportTheme.textSecondary)
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
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .padding(.horizontal, SupportTheme.Spacing.m)
    }
}

struct RecentResultCard: View {
    let response: AssessmentResponse

    var severityColor: Color {
        switch response.severityLevel.lowercased() {
        case "minimal": return SupportTheme.accent
        case "mild": return SupportTheme.accent
        case "moderate": return SupportTheme.accent
        case "moderately_severe", "moderately severe": return SupportTheme.accent
        case "severe": return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(response.availableScore.map { "Score: \($0)" } ?? "Score unavailable")
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundColor(SupportTheme.accent)

                Text(response.availableScore == nil ? "Retake this assessment for a current score" : response.severityLevel)
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundColor(severityColor)

                if response.scoreStatus == .recalculated {
                    Text("Recalculated from saved answers").font(.caption).foregroundColor(SupportTheme.textSecondary)
                }
                Text(response.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(.caption, design: .default).weight(.regular))
                    .foregroundColor(SupportTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.subheadline).weight(.semibold))
                .foregroundColor(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.s)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

struct OutcomeGoalCard: View {
    let goal: OutcomeGoal

    let assessmentType: AssessmentType?
    let currentScore: Int?

    var progress: Double? {
        guard let assessmentType else { return nil }
        return goal.progress(currentScore: currentScore, type: assessmentType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Goal: \(goal.targetScore) by \(goal.targetDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(SupportTheme.accent)

                    Text("From baseline: \(goal.baselineScore)")
                        .font(.system(.caption, design: .default).weight(.regular))
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()
            }

            if let progress {
                ProgressView(value: progress)
                    .tint(SupportTheme.accent)
            } else {
                Text(assessmentType.map { goal.requiresScoreReview(for: $0) } == true
                     ? "Review this target after scoring corrections" : "No current score available")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .padding(SupportTheme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(SupportTheme.accent)
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

#if DEBUG
#Preview {
    OutcomeHomeView(
        outcomeService: OutcomeTrackingService(supabase: .mock, authService: SupabaseAuthService()),
        authService: SupabaseAuthService()
    )
}
#endif
