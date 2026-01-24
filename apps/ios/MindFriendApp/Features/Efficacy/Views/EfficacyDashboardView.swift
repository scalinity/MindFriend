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
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading insights...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Failed to Load Insights")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task {
                    await viewModel.loadDashboard()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Dashboard Content

    private func dashboardContent(data: EfficacyDashboardData) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Insights Summary Cards
                insightsSummary(insights: data.insights)

                // Top Exercises Section
                if !data.topExercises.isEmpty {
                    topExercisesSection(exercises: data.topExercises)
                }

                // Recent Sessions Section
                if !data.recentSessions.isEmpty {
                    recentSessionsSection(sessions: data.recentSessions)
                }
            }
            .padding()
        }
    }

    // MARK: - Insights Summary

    private func insightsSummary(insights: DashboardInsights) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                insightCard(
                    title: "Avg Efficacy",
                    value: String(format: "%.0f", insights.averageEfficacy),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue
                )

                insightCard(
                    title: "Breakthroughs",
                    value: "\(insights.totalBreakthroughs)",
                    icon: "sparkles",
                    color: .purple
                )
            }

            if let context = insights.mostEffectiveContext {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Most effective: \(context)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            ForEach(insights.messages, id: \.self) { message in
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    private func insightCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Top Exercises Section

    private func topExercisesSection(exercises: [EfficacyDashboardData.TopExercise]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Exercises")
                .font(.headline)
                .padding(.horizontal)

            ForEach(exercises, id: \.exerciseId) { exercise in
                topExerciseRow(exercise: exercise)
            }
        }
    }

    private func topExerciseRow(exercise: EfficacyDashboardData.TopExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.headline)

                    if let context = exercise.bestContext {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    efficacyStars(score: exercise.efficacyScore)

                    HStack(spacing: 4) {
                        trendIndicator(trend: exercise.trend)
                        Text("\(exercise.completionCount)×")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            ProgressView(value: exercise.efficacyScore / 100)
                .tint(efficacyColor(score: exercise.efficacyScore))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func efficacyStars(score: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(index < Int(score / 20) ? .yellow : .gray.opacity(0.3))
            }
        }
    }

    private func trendIndicator(trend: UserEfficacyProfile.EfficacyTrend) -> some View {
        Group {
            switch trend {
            case .improving:
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.green)
            case .stable:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .declining:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }

    private func efficacyColor(score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .blue }
        else if score >= 40 { return .orange }
        else { return .red }
    }

    // MARK: - Recent Sessions Section

    private func recentSessionsSection(sessions: [EfficacyDashboardData.RecentSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
                .padding(.horizontal)

            ForEach(sessions, id: \.sessionId) { session in
                recentSessionRow(session: session)
            }
        }
    }

    private func recentSessionRow(session: EfficacyDashboardData.RecentSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.exerciseName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(session.completedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if session.breakthroughDetected {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.purple)
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
