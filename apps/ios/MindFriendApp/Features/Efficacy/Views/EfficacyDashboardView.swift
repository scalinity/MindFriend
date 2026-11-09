//
//  EfficacyDashboardView.swift
//  MindFriendApp
//
//  Efficacy Dashboard - Shows top exercises, recent sessions, and insights
//

import SwiftUI

struct EfficacyDashboardView: View {
    @StateObject private var viewModel: EfficacyDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    init(efficacyEngine: InterventionEfficacyEngine) {
        _viewModel = StateObject(wrappedValue: EfficacyDashboardViewModel(efficacyEngine: efficacyEngine))
    }

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .loaded(let data):
                    dashboardContent(data: data)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .supportScreen()
            .navigationTitle("Efficacy Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadDashboard()
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
            Text("Loading insights...")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
        }
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle))
                .foregroundColor(SupportTheme.accent)

            Text("Failed to Load Insights")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Button("Try Again") {
                Task {
                    await viewModel.loadDashboard()
                }
            }
            .buttonStyle(.supportSecondary)
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Dashboard Content

    private func dashboardContent(data: EfficacyDashboardData) -> some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if data.recentSessions.isEmpty {
                    ContentUnavailableView(
                        "Efficacy unavailable",
                        systemImage: "waveform.path",
                        description: Text("No supported emotional measurements have been recorded. You can still complete exercises and receive suggestions.")
                    )
                } else {
                    insightsSummary(insights: data.insights)
                }

                // Top Exercises Section
                if !data.topExercises.isEmpty {
                    topExercisesSection(exercises: data.topExercises)
                }

                // Recent Sessions Section
                if !data.recentSessions.isEmpty {
                    recentSessionsSection(sessions: data.recentSessions)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
    }

    // MARK: - Insights Summary

    private func insightsSummary(insights: DashboardInsights) -> some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.m) {
                insightCard(
                    title: "Avg Efficacy",
                    value: String(format: "%.0f", insights.averageEfficacy),
                    icon: "chart.line.uptrend.xyaxis",
                    color: SupportTheme.accent
                )

                insightCard(
                    title: "Breakthroughs",
                    value: "\(insights.totalBreakthroughs)",
                    icon: "sparkles",
                    color: SupportTheme.accent
                )
            }

            if let context = insights.mostEffectiveContext {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(SupportTheme.accent)
                    Text("Most effective: \(context)")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }

            ForEach(insights.messages, id: \.self) { message in
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(SupportTheme.accent)
                    Text(message)
                        .font(.subheadline)
                    Spacer()
                }
                .supportCard()
            }
        }
    }

    private func insightCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
    }

    // MARK: - Top Exercises Section

    private func topExercisesSection(exercises: [EfficacyDashboardData.TopExercise]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Top Exercises")
                .font(.headline)
                .padding(.horizontal, SupportTheme.Spacing.m)

            ForEach(exercises, id: \.exerciseId) { exercise in
                topExerciseRow(exercise: exercise)
            }
        }
    }

    private func topExerciseRow(exercise: EfficacyDashboardData.TopExercise) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(exercise.exerciseName)
                        .font(.headline)

                    if let context = exercise.bestContext {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    efficacyStars(score: exercise.efficacyScore)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        trendIndicator(trend: exercise.trend)
                        Text("\(exercise.completionCount)×")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }
            }

            ProgressView(value: exercise.efficacyScore / 100)
                .tint(efficacyColor(score: exercise.efficacyScore))
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func efficacyStars(score: Double) -> some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            ForEach(0..<5) { index in
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(index < Int(score / 20) ? .yellow : SupportTheme.textSecondary.opacity(0.3))
            }
        }
    }

    private func trendIndicator(trend: UserEfficacyProfile.EfficacyTrend) -> some View {
        Group {
            switch trend {
            case .improving:
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(SupportTheme.accent)
            case .stable:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(SupportTheme.accent)
            case .declining:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }

    private func efficacyColor(score: Double) -> Color {
        if score >= 80 { return SupportTheme.accent }
        else if score >= 60 { return SupportTheme.accent }
        else if score >= 40 { return SupportTheme.accent }
        else { return .red }
    }

    // MARK: - Recent Sessions Section

    private func recentSessionsSection(sessions: [EfficacyDashboardData.RecentSession]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Recent Sessions")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, SupportTheme.Spacing.m)

            ForEach(sessions, id: \.sessionId) { session in
                recentSessionRow(session: session)
            }
        }
    }

    private func recentSessionRow(session: EfficacyDashboardData.RecentSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(session.exerciseName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(session.completedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    if session.breakthroughDetected {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(SupportTheme.accent)
                    }

                    Text(String(format: "%.0f", session.efficacyScore))
                        .font(.headline)
                        .foregroundColor(efficacyColor(score: session.efficacyScore))
                }

                Text(session.netChange >= 0 ? "+\(String(format: "%.1f", session.netChange))" : String(format: "%.1f", session.netChange))
                    .font(.caption)
                    .foregroundColor(session.netChange >= 0 ? .green : .red)
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    EfficacyDashboardView(
        efficacyEngine: InterventionEfficacyEngine(
            tracker: TrajectoryTracker(supabase: .init(supabaseURL: URL(string: "https://example.com")!, supabaseKey: "key")),
            calculator: EfficacyCalculator(),
            recommender: EfficacyBasedRecommender(supabase: .init(supabaseURL: URL(string: "https://example.com")!, supabaseKey: "key")),
            supabase: .init(supabaseURL: URL(string: "https://example.com")!, supabaseKey: "key")
        )
    )
}
