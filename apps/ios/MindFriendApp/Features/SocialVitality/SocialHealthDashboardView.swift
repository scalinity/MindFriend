//
//  SocialHealthDashboardView.swift
//  MindFriend
//
//  Created: 2026-01-23
//  Feature: N004 - Social Vitality Index
//

import SwiftUI
import Supabase

struct SocialHealthDashboardView: View {
    @StateObject private var engine: SocialVitalityEngine
    @State private var showSettings = false

    init(engine: SocialVitalityEngine) {
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if engine.isLoading {
                        ProgressView("Loading your social vitality...")
                    } else if let dashboard = engine.dashboard {
                        // Score Display
                        scoreCard(dashboard: dashboard)

                        // Components Breakdown
                        componentsView(components: dashboard.components)

                        // Top Supporters
                        if !dashboard.topSupporters.isEmpty {
                            supportersView(supporters: dashboard.topSupporters)
                        }

                        // Insight
                        if let insight = dashboard.insight {
                            insightView(insight: insight)
                        }

                        // Alert Status
                        alertStatusView(status: dashboard.alertStatus)
                    } else if let error = engine.error {
                        errorView(error: error)
                    } else {
                        emptyStateView()
                    }
                }
                .padding()
            }
            .navigationTitle("Social Vitality")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                // TODO: Settings view
                Text("Settings Coming Soon")
            }
            .task {
                do {
                    try await engine.fetchDashboard()
                } catch {
                    print("Error fetching dashboard: \(error)")
                }
            }
            .refreshable {
                do {
                    try await engine.fetchDashboard()
                } catch {
                    print("Error refreshing dashboard: \(error)")
                }
            }
        }
    }

    // MARK: - Score Card

    @ViewBuilder
    private func scoreCard(dashboard: SocialVitalityDashboard) -> some View {
        VStack(spacing: 16) {
            // Score Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 180, height: 180)

                Circle()
                    .trim(from: 0, to: CGFloat(dashboard.currentScore) / 100.0)
                    .stroke(trendColor(dashboard.trend), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: dashboard.currentScore)

                VStack {
                    Text("\(dashboard.currentScore)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text("Social Vitality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Trend Indicator
            HStack {
                Image(systemName: trendIcon(dashboard.trend))
                    .foregroundColor(trendColor(dashboard.trend))
                Text(dashboard.trend.displayName)
                    .font(.headline)
            }

            // Weekly Change
            Text("Weekly Change: \(dashboard.weeklyChangeFormatted)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Components View

    @ViewBuilder
    private func componentsView(components: SocialVitalityDashboard.ScoreComponents) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Components")
                .font(.headline)

            componentBar(label: "Frequency", value: components.frequency, max: 25)
            componentBar(label: "Depth", value: components.depth, max: 25)
            componentBar(label: "Reciprocity", value: components.reciprocity, max: 25)
            componentBar(label: "Diversity", value: components.diversity, max: 25)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    @ViewBuilder
    private func componentBar(label: String, value: Int, max: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(value) / CGFloat(max), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Supporters View

    @ViewBuilder
    private func supportersView(supporters: [SocialVitalityDashboard.SupporterInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Supporters")
                .font(.headline)

            ForEach(supporters) { supporter in
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.green)

                    Text(supporter.name)
                        .font(.subheadline)

                    Spacer()

                    Text(supporter.correlationPercentage)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Insight View

    @ViewBuilder
    private func insightView(insight: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)

            Text(insight)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Alert Status View

    @ViewBuilder
    private func alertStatusView(status: SocialVitalityDashboard.AlertStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peer Support Alerts")
                .font(.headline)

            HStack {
                Image(systemName: status.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(status.enabled ? .green : .gray)

                Text(status.enabled ? "Enabled" : "Disabled")
                    .font(.subheadline)

                Spacer()

                if status.enabled {
                    Text("\(status.supportersConfigured) supporters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                showSettings = true
            } label: {
                Text("Configure")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: SocialVitalityEngine.EngineError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(error.errorDescription ?? "An error occurred")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    try? await engine.fetchDashboard()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("We're collecting data about your social connections")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Keep engaging in circles, and your social vitality score will appear here in a few days!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    private func trendColor(_ trend: SocialVitalityScore.ScoreTrend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        case .plummeting: return .red
        }
    }

    private func trendIcon(_ trend: SocialVitalityScore.ScoreTrend) -> String {
        switch trend {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.forward"
        case .declining: return "arrow.down.right"
        case .plummeting: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Preview

#Preview {
    SocialHealthDashboardViewPreview()
}

private struct SocialHealthDashboardViewPreview: View {
    var body: some View {
        SocialHealthDashboardView(engine: createMockEngine())
    }

    private func createMockEngine() -> SocialVitalityEngine {
        let engine = SocialVitalityEngine(supabase: createMockClient())
        // Set mock dashboard data
        engine.dashboard = SocialVitalityDashboard(
            currentScore: 72,
            trend: .stable,
            components: SocialVitalityDashboard.ScoreComponents(
                frequency: 20,
                depth: 18,
                reciprocity: 22,
                diversity: 12
            ),
            weeklyChange: -3,
            topSupporters: [
                SocialVitalityDashboard.SupporterInfo(id: "1", name: "Sarah", correlation: 0.45),
                SocialVitalityDashboard.SupporterInfo(id: "2", name: "Mike", correlation: 0.38)
            ],
            insight: "Your mood tends to improve after connecting with Sarah.",
            alertStatus: SocialVitalityDashboard.AlertStatus(enabled: true, supportersConfigured: 2)
        )
        return engine
    }

    private func createMockClient() -> SupabaseClient {
        // Create a mock client using the Supabase.createClient method
        // This requires a valid URL and key, but for preview purposes,
        // we use placeholder values
        return SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "placeholder-key"
        )
    }
}
