import SwiftUI

/// Sleep insights and weekly reports view
struct SleepInsightsView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = SleepInsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if !viewModel.insights.isEmpty {
                    ForEach(viewModel.insights) { insight in
                        insightCard(insight)
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Sleep Insights")
        .task {
            await viewModel.loadInsights(trackingService: dependencies.sleepTrackingService)
        }
        .refreshable {
            await viewModel.refresh(trackingService: dependencies.sleepTrackingService)
        }
    }

    @ViewBuilder
    private func insightCard(_ insight: SleepInsight) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: insight.insightType.icon)
                    .foregroundColor(SupportTheme.accent)

                Text(insight.insightData.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if !insight.viewed {
                    Circle()
                        .fill(SupportTheme.accent)
                        .frame(width: 8, height: 8)
                }
            }

            Text(insight.insightData.message)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            if let recommendation = insight.insightData.recommendation {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(SupportTheme.Celebration.gold)

                    Text(recommendation)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textPrimary)
                }
                .padding(SupportTheme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)
            }

            HStack {
                if let trend = insight.insightData.trend, let trendIcon = insight.insightData.trendIcon {
                    Image(systemName: trendIcon)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)

                    Text(trend.capitalized)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                Text(insight.generatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .padding()
        .background(SupportTheme.field)
        .cornerRadius(SupportTheme.controlRadius)
        .onAppear {
            if !insight.viewed {
                viewModel.markViewed(insight, trackingService: dependencies.sleepTrackingService)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(SupportTheme.textSecondary)

            Text("No Insights Yet")
                .font(.title3)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text("Track your sleep for at least 7 days to receive personalized insights")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, SupportTheme.Spacing.xl)
    }
}

// MARK: - View Model

@MainActor
final class SleepInsightsViewModel: ObservableObject {
    @Published var insights: [SleepInsight] = []
    @Published var isLoading = false

    func loadInsights(trackingService: SleepTrackingService) async {
        isLoading = true
        defer { isLoading = false }

        do {
            insights = try await trackingService.fetchInsights()
        } catch {
            print("Failed to load insights: \(error)")
        }
    }

    func refresh(trackingService: SleepTrackingService) async {
        do {
            _ = try await trackingService.analyzeSleepPatterns()
        } catch {
            print("Failed to generate new insights: \(error)")
        }

        await loadInsights(trackingService: trackingService)
    }

    func markViewed(_ insight: SleepInsight, trackingService: SleepTrackingService) {
        Task {
            do {
                try await trackingService.markInsightViewed(id: insight.id)
            } catch {
                print("Failed to mark insight as viewed: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        SleepInsightsView()
            .environmentObject(DependencyContainer.preview)
    }
}
