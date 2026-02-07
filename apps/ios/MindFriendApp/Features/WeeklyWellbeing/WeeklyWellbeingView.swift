import SwiftUI

// MARK: - Weekly Wellbeing Check-In View

struct WeeklyWellbeingView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = WeeklyWellbeingViewModel()

    @State private var currentMetricIndex = 0
    @State private var showingRecap = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock")
                    }
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Weekly Wellbeing Check")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Take a moment to reflect on your week. Your answers are private and help us support you better.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Question \(currentMetricIndex + 1) of \(viewModel.metrics.count + 3)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(.blue)
        }
    }

    private var progress: Double {
        Double(currentMetricIndex) / Double(viewModel.metrics.count + 3)
    }

    // MARK: - Metric Section

    private var metricSection: some View {
        let metric = viewModel.metrics[currentMetricIndex]

        return VStack(spacing: 24) {
            // Metric header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: metric.category.icon)
                        .font(.title)
                        .foregroundStyle(colorForCategory(metric.category))
                        .frame(width: 50, height: 50)
                        .background(colorForCategory(metric.category).opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.category.displayName)
                            .font(.headline)

                        Text(metric.category.question)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Score slider
            VStack(spacing: 16) {
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(metric.category.higherIsBetter ? "High" : "Low")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        let contextIndex = currentMetricIndex - viewModel.metrics.count

        return VStack(spacing: 24) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.headline)

            TextEditor(text: binding)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: binding.wrappedValue) { _, newValue in
                    if newValue.count > 2000 {
                        binding.wrappedValue = String(newValue.prefix(2000))
                    }
                }

            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        HStack(spacing: 16) {
            if currentMetricIndex > 0 {
                Button {
                    withAnimation {
                        currentMetricIndex -= 1
                    }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if currentMetricIndex < viewModel.metrics.count + 2 {
                Button {
                    withAnimation {
                        currentMetricIndex += 1
                    }
                } label: {
                    Text(currentMetricIndex >= viewModel.metrics.count + 1 ? "Complete" : "Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.top)
    }

    // MARK: - Helpers

    private func colorForCategory(_ category: WellbeingCategory) -> Color {
        switch category {
        case .mood: return .yellow
        case .energy: return .orange
        case .stress: return .red
        case .sleep: return .indigo
        case .social: return .blue
        case .purpose: return .purple
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 1...3: return .red
        case 4...6: return .orange
        case 7...8: return .yellow
        case 9...10: return .green
        default: return .gray
        }
    }

    private func trendIcon(_ trend: WellbeingTrend?) -> String {
        trend?.icon ?? "equal.circle.fill"
    }

    private func trendColor(_ trend: WellbeingTrend?) -> Color {
        guard let trend = trend else { return .gray }
        switch trend {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .gray
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
                VStack(spacing: 24) {
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
            .background(Color(.systemGroupedBackground))
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
        VStack(spacing: 12) {
            Text("Weekly Score")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1f", check.averageScore))
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(scoreColor)

            HStack {
                Image(systemName: check.trend?.icon ?? "equal.circle.fill")
                    .foregroundStyle(trendColor)
                Text(trendDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let previous = check.previousWeekScore {
                Text("\(check.totalScore) vs \(previous) last week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var metricsBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)

            VStack(spacing: 8) {
                metricRow(name: "Mood", score: check.overallMood, icon: "face.smiling", color: .yellow)
                metricRow(name: "Energy", score: check.energyLevel, icon: "bolt.fill", color: .orange)
                metricRow(name: "Stress", score: check.stressLevel, icon: "waveform.path", color: .red)
                metricRow(name: "Sleep", score: check.sleepQuality, icon: "moon.fill", color: .indigo)
                metricRow(name: "Social", score: check.socialConnection, icon: "person.2.fill", color: .blue)
                metricRow(name: "Purpose", score: check.senseOfPurpose, icon: "sparkles", color: .purple)
            }
        }
    }

    private func metricRow(name: String, score: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(name)
                .font(.subheadline)

            Spacer()

            Text("\(score)/10")
                .font(.subheadline)
                .fontWeight(.medium)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(score) / 10, height: 8)
                }
            }
            .frame(width: 100, height: 8)
        }
    }

    private func insightsSection(_ insights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)

            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)

                    Text(insight)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                // Share with circle if enabled
            } label: {
                Label("Share with Circle", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                // View history
            } label: {
                Text("View History")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var scoreColor: Color {
        switch check.averageScore {
        case 0...4: return .red
        case 4...6: return .orange
        case 6...8: return .yellow
        case 8...10: return .green
        default: return .gray
        }
    }

    private var trendColor: Color {
        guard let trend = check.trend else { return .gray }
        switch trend {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .gray
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.createdAt, style: .date)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Score: \(check.totalScore)/60")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let trend = check.trend {
                            Image(systemName: trend.icon)
                                .foregroundStyle(trendColor(trend))
                        }
                    }
                }
            }
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
        case .improving: return .green
        case .declining: return .red
        case .stable: return .gray
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
