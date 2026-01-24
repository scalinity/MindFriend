import SwiftUI

/// Sleep insights and weekly reports view
struct SleepInsightsView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = SleepInsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.insightType.icon)
                    .foregroundColor(.accentColor)

                Text(insight.insightData.title)
                    .font(.headline)

                Spacer()

                if !insight.viewed {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }

            Text(insight.insightData.message)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let recommendation = insight.insightData.recommendation {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)

                    Text(recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }

            HStack {
                if let trend = insight.insightData.trend, let trendIcon = insight.insightData.trendIcon {
                    Image(systemName: trendIcon)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(trend.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(insight.generatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            if !insight.viewed {
                viewModel.markViewed(insight, trackingService: dependencies.sleepTrackingService)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Insights Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Track your sleep for at least 7 days to receive personalized insights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 60)
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
