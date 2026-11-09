import SwiftUI

// MARK: - Weekly Wellbeing Check-In View

struct WeeklyWellbeingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = WeeklyWellbeingViewModel()

    @State private var currentMetricIndex = 0
    @State private var showingRecap = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Header
                    headerSection

                    // Progress
                    progressSection

                    // Current metric slider or input
                    if currentMetricIndex < viewModel.metrics.count {
                        metricSection
                    } else {
                        // Context questions
                        contextSection
                    }

                    // Navigation
                    navigationSection
                }
                .padding()
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Weekly Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .accessibilityLabel("Check-in history")
                }
            }
            .sheet(isPresented: $showingRecap) {
                if let check = viewModel.completedCheck {
                    WeeklyWellbeingRecapView(check: check)
                }
            }
            .sheet(isPresented: $showingHistory) {
                WeeklyWellbeingHistoryView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadPreviousCheck(container: container)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.showError {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle")
                        Button("OK") { viewModel.showError = false }
                            .buttonStyle(.supportSecondary)
                    }
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.accent)

            Text("Weekly Wellbeing Check")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text("Take a moment to reflect on your week. Your answers are private and help us support you better.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text("Question \(currentMetricIndex + 1) of \(viewModel.metrics.count + 3)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()

                Text("\(Int(progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            ProgressView(value: progress)
                .tint(SupportTheme.accent)
        }
    }

    private var progress: Double {
        Double(currentMetricIndex) / Double(viewModel.metrics.count + 3)
    }

    // MARK: - Metric Section

    private var metricSection: some View {
        let metric = viewModel.metrics[currentMetricIndex]

        return VStack(spacing: SupportTheme.Spacing.l) {
            // Metric header
            VStack(spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Image(systemName: metric.category.icon)
                        .font(.title)
                        .foregroundStyle(colorForCategory(metric.category))
                        .frame(width: 50, height: 50)
                        .background(colorForCategory(metric.category).opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(metric.category.displayName)
                            .font(.headline)

                        Text(metric.category.question)
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()
                }

                // Previous score indicator
                if let _ = metric.previousScore {
                    HStack {
                        Image(systemName: trendIcon(metric.trend))
                            .foregroundStyle(trendColor(metric.trend))

                        Text(metric.changeDescription)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }

            // Score slider
            VStack(spacing: SupportTheme.Spacing.m) {
                // Score display
                Text("\(viewModel.scores[metric.category] ?? 5)")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(colorForScore(viewModel.scores[metric.category] ?? 5))

                // Slider
                Slider(
                    value: Binding(
                        get: { Double(viewModel.scores[metric.category] ?? 5) },
                        set: { viewModel.scores[metric.category] = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .tint(colorForCategory(metric.category))

                // Labels
                HStack {
                    Text(metric.category.higherIsBetter ? "Low" : "High")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Spacer()
                    Text(metric.category.higherIsBetter ? "High" : "Low")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .padding()
            .background(SupportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        let contextIndex = currentMetricIndex - viewModel.metrics.count

        return VStack(spacing: SupportTheme.Spacing.l) {
            switch contextIndex {
            case 0:
                contextQuestion(
                    question: "What was the highlight of your week?",
                    prompt: "Share a moment that made you feel good...",
                    binding: $viewModel.highlight
                )
            case 1:
                contextQuestion(
                    question: "What was most challenging?",
                    prompt: "What трудность did you face?",
                    binding: $viewModel.challenge
                )
            case 2:
                contextQuestion(
                    question: "What are you grateful for?",
                    prompt: "Something small that brought you joy...",
                    binding: $viewModel.gratitude
                )
            default:
                EmptyView()
            }
        }
    }

    private func contextQuestion(question: String, prompt: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text(question)
                .font(.headline)

            TextEditor(text: binding)
                .scrollContentBackground(.hidden)
                .supportField()
                .frame(minHeight: 100)
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .onChange(of: binding.wrappedValue) { _, newValue in
                    if newValue.count > 2000 {
                        binding.wrappedValue = String(newValue.prefix(2000))
                    }
                }

            Text(prompt)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            if currentMetricIndex > 0 {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        currentMetricIndex -= 1
                    }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .buttonStyle(.supportSecondary)
            }

            if currentMetricIndex < viewModel.metrics.count + 2 {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        currentMetricIndex += 1
                    }
                } label: {
                    Text(currentMetricIndex >= viewModel.metrics.count + 1 ? "Complete" : "Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .buttonStyle(.supportPrimary)
            }
        }
        .padding(.top)
    }

    // MARK: - Helpers

    private func colorForCategory(_ category: WellbeingCategory) -> Color {
        switch category {
        case .mood: return SupportTheme.Celebration.gold
        case .energy: return SupportTheme.accent
        case .stress: return .red
        case .sleep: return SupportTheme.accent
        case .social: return SupportTheme.accent
        case .purpose: return SupportTheme.accent
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 1...3: return .red
        case 4...6: return SupportTheme.accent
        case 7...8: return SupportTheme.Celebration.gold
        case 9...10: return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    private func trendIcon(_ trend: WellbeingTrend?) -> String {
        trend?.icon ?? "equal.circle.fill"
    }

    private func trendColor(_ trend: WellbeingTrend?) -> Color {
        guard let trend = trend else { return SupportTheme.textSecondary }
        switch trend {
        case .improving: return SupportTheme.accent
        case .declining: return .red
        case .stable: return SupportTheme.textSecondary
        }
    }
}

// MARK: - Weekly Wellbeing Recap View

struct WeeklyWellbeingRecapView: View {
    @Environment(\.dismiss) private var dismiss
    let check: WeeklyWellbeingCheck

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Score card
                    scoreCard

                    // Metrics breakdown
                    metricsBreakdown

                    // Insights
                    if let insights = generateInsights() {
                        insightsSection(insights)
                    }

                    // Actions
                    actionsSection
                }
                .padding()
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Your Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var scoreCard: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Text("Weekly Score")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            Text(String(format: "%.1f", check.averageScore))
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(scoreColor)

            HStack {
                Image(systemName: check.trend?.icon ?? "equal.circle.fill")
                    .foregroundStyle(trendColor)
                Text(trendDescription)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            if let previous = check.previousWeekScore {
                Text("\(check.totalScore) vs \(previous) last week")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private var metricsBreakdown: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Category Breakdown")
                .font(.headline)

            VStack(spacing: SupportTheme.Spacing.xs) {
                metricRow(name: "Mood", score: check.overallMood, icon: "face.smiling", color: SupportTheme.Celebration.gold)
                metricRow(name: "Energy", score: check.energyLevel, icon: "bolt.fill", color: SupportTheme.accent)
                metricRow(name: "Stress", score: check.stressLevel, icon: "waveform.path", color: .red)
                metricRow(name: "Sleep", score: check.sleepQuality, icon: "moon.fill", color: SupportTheme.accent)
                metricRow(name: "Social", score: check.socialConnection, icon: "person.2.fill", color: SupportTheme.accent)
                metricRow(name: "Purpose", score: check.senseOfPurpose, icon: "sparkles", color: SupportTheme.accent)
            }
        }
    }

    private func metricRow(name: String, score: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(minWidth: 24)

            Text(name)
                .font(.subheadline)

            Spacer()

            Text("\(score)/10")
                .font(.subheadline)
                .fontWeight(.medium)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.textSecondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(score) / 10, height: 8)
                }
            }
            .frame(width: 100, height: 8)
        }
    }

    private func insightsSection(_ insights: [String]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Insights")
                .font(.headline)

            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(SupportTheme.Celebration.gold)

                    Text(insight)
                        .font(.subheadline)
                }
                .padding()
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Button {
                // Share with circle if enabled
            } label: {
                Label("Share with Circle", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .buttonStyle(.supportPrimary)

            Button {
                // View history
            } label: {
                Text("View History")
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .buttonStyle(.supportSecondary)
        }
    }

    private var scoreColor: Color {
        switch check.averageScore {
        case 0...4: return .red
        case 4...6: return SupportTheme.accent
        case 6...8: return SupportTheme.Celebration.gold
        case 8...10: return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    private var trendColor: Color {
        guard let trend = check.trend else { return SupportTheme.textSecondary }
        switch trend {
        case .improving: return SupportTheme.accent
        case .declining: return .red
        case .stable: return SupportTheme.textSecondary
        }
    }

    private var trendDescription: String {
        guard let trend = check.trend else { return "No previous data" }
        switch trend {
        case .improving: return "Getting better"
        case .declining: return "Room for improvement"
        case .stable: return "Staying steady"
        }
    }

    private func generateInsights() -> [String]? {
        var insights: [String] = []

        // Generate insights based on scores
        if check.overallMood >= 8 {
            insights.append("Your mood has been consistently positive this week!")
        } else if check.overallMood <= 4 {
            insights.append("It's been a challenging week emotionally. Be kind to yourself.")
        }

        if check.stressLevel >= 8 {
            insights.append("High stress levels might benefit from breathing exercises.")
        }

        if check.sleepQuality <= 4 {
            insights.append("Sleep quality impacts many areas of wellbeing. Consider a sleep routine.")
        }

        if check.socialConnection <= 4 {
            insights.append("Connecting with others can boost your mood and sense of purpose.")
        }

        return insights.isEmpty ? nil : insights
    }
}

// MARK: - Weekly Wellbeing History View

struct WeeklyWellbeingHistoryView: View {
    @ObservedObject var viewModel: WeeklyWellbeingViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.history) { check in
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(check.createdAt, style: .date)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Score: \(check.totalScore)/60")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Spacer()

                        if let trend = check.trend {
                            Image(systemName: trend.icon)
                                .foregroundStyle(trendColor(trend))
                        }
                    }
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        // Dismiss
                    }
                }
            }
        }
    }

    private func trendColor(_ trend: WellbeingTrend) -> Color {
        switch trend {
        case .improving: return SupportTheme.accent
        case .declining: return .red
        case .stable: return SupportTheme.textSecondary
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    WeeklyWellbeingView()
        .environmentObject(DependencyContainer.preview)
}
#endif
