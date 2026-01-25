import SwiftUI
import Supabase

/// Community Wisdom Feed showing personalized recommendations
struct WisdomFeedView: View {
    @EnvironmentObject private var wisdomService: WisdomService
    @State private var selectedCategory: StrategyCategory?
    @State private var showingContributeSheet = false
    @State private var showingError = false
    
    var body: some View {
        mainContent
            .navigationTitle("Community Wisdom")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingContributeSheet) {
                ContributeStrategySheet()
            }
            .refreshable { await refreshWisdom() }
            .task { await refreshWisdom() }
            .overlay { loadingOverlay }
            .alert("Unable to Load", isPresented: $showingError) {
                alertButtons
            } message: {
                Text(wisdomService.error?.localizedDescription ?? "Please try again later.")
            }
            .onChange(of: wisdomService.error) { _, newError in
                showingError = newError != nil
            }
    }

    // MARK: - View Components

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                notAloneSection
                recommendationsSection
                strategiesSection
                emptyStateSection
                Spacer(minLength: 100)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var notAloneSection: some View {
        if let notAlone = wisdomService.notAloneInsight {
            NotAloneCard(insight: notAlone)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You're not alone. \(notAlone.content)")
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if !wisdomService.recommendations.isEmpty {
            WisdomRecommendationsSection(
                recommendations: wisdomService.recommendations,
                onFeedback: { id, helpful in
                    Task {
                        try? await wisdomService.recordFeedback(
                            recommendationId: id,
                            helpful: helpful
                        )
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var strategiesSection: some View {
        if !wisdomService.strategies.isEmpty {
            StrategiesSection(
                strategies: wisdomService.strategies,
                onVote: { id, voteType in
                    Task {
                        try? await wisdomService.voteStrategy(
                            strategyId: id,
                            voteType: voteType
                        )
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if !wisdomService.isLoading &&
           wisdomService.recommendations.isEmpty &&
           wisdomService.strategies.isEmpty {
            EmptyWisdomState(
                canReceive: wisdomService.canReceiveRecommendations
            )
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if wisdomService.isLoading && wisdomService.recommendations.isEmpty {
            ProgressView()
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.1))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingContributeSheet = true
            } label: {
                Image(systemName: "plus.bubble")
            }
            .disabled(!wisdomService.canContribute)
            .accessibilityLabel("Share a strategy")
        }
    }

    @ViewBuilder
    private var alertButtons: some View {
        Button("Retry") {
            Task { await refreshWisdom() }
        }
        Button("OK", role: .cancel) {
            wisdomService.clearError()
        }
    }
    
    private func refreshWisdom() async {
        do {
            try await wisdomService.fetchConsent()
            try await wisdomService.fetchRecommendations()
            try await wisdomService.fetchStrategies(category: selectedCategory ?? .general)
        } catch {
            // Error is handled by the service and shown via alert
            #if DEBUG
            print("Failed to refresh wisdom: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Not Alone Card

private struct NotAloneCard: View {
    let insight: InsightResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                Text("You're Not Alone")
                    .font(.headline)
                Spacer()
            }

            Text(insight.content)
                .font(.body)
                .foregroundColor(.secondary)

            HStack {
                Label("\(insight.sampleSize)+", systemImage: "person.2")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                WisdomConfidenceBadge(score: insight.confidenceScore)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.pink.opacity(0.1))
        )
    }
}

// MARK: - Recommendations Section

private struct WisdomRecommendationsSection: View {
    let recommendations: [InsightResponse]
    let onFeedback: (UUID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For You")
                .font(.headline)

            ForEach(recommendations) { rec in
                WisdomRecommendationCard(
                    recommendation: rec,
                    onFeedback: onFeedback
                )
            }
        }
    }
}

private struct WisdomRecommendationCard: View {
    let recommendation: InsightResponse
    let onFeedback: (UUID, Bool) -> Void
    @State private var feedbackGiven = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recommendation.content)
                .font(.body)

            HStack {
                Label("\(recommendation.sampleSize)+", systemImage: "person.2")
                    .font(.caption)
                    .foregroundColor(.secondary)

                WisdomConfidenceBadge(score: recommendation.confidenceScore)

                Spacer()

                if !feedbackGiven {
                    HStack(spacing: 16) {
                        Button {
                            onFeedback(recommendation.id, true)
                            feedbackGiven = true
                        } label: {
                            Image(systemName: "hand.thumbsup")
                                .foregroundColor(.green)
                        }
                        .accessibilityLabel("Mark as helpful")

                        Button {
                            onFeedback(recommendation.id, false)
                            feedbackGiven = true
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .foregroundColor(.red)
                        }
                        .accessibilityLabel("Mark as not helpful")
                    }
                } else {
                    Text("Thanks!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Strategies Section

private struct StrategiesSection: View {
    let strategies: [CommunityStrategy]
    let onVote: (UUID, VoteType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Strategies")
                .font(.headline)

            ForEach(strategies) { strategy in
                StrategyCard(strategy: strategy, onVote: onVote)
            }
        }
    }
}

private struct StrategyCard: View {
    let strategy: CommunityStrategy
    let onVote: (UUID, VoteType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: strategy.category.iconName)
                    .foregroundColor(.accentColor)
                Text(strategy.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(strategy.strategyText)
                .font(.body)

            if let context = strategy.context {
                Text(context)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            HStack {
                // Helpful percentage
                if strategy.helpfulCount + strategy.notHelpfulCount > 0 {
                    Label(
                        "\(strategy.helpfulPercentage)% helpful",
                        systemImage: "hand.thumbsup.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.green)
                }

                Spacer()

                // Vote buttons
                HStack(spacing: 12) {
                    Button {
                        onVote(strategy.id, .helpful)
                    } label: {
                        Image(systemName: strategy.myVote == .helpful
                            ? "hand.thumbsup.fill"
                            : "hand.thumbsup")
                            .foregroundColor(.green)
                    }
                    .disabled(strategy.myVote != nil)

                    Button {
                        onVote(strategy.id, .notHelpful)
                    } label: {
                        Image(systemName: strategy.myVote == .notHelpful
                            ? "hand.thumbsdown.fill"
                            : "hand.thumbsdown")
                            .foregroundColor(.red)
                    }
                    .disabled(strategy.myVote != nil)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Confidence Badge

private struct WisdomConfidenceBadge: View {
    let score: Double

    var label: String {
        switch score {
        case 0.9...1.0: return "Very High"
        case 0.75..<0.9: return "High"
        case 0.5..<0.75: return "Moderate"
        default: return "Low"
        }
    }

    var color: Color {
        switch score {
        case 0.9...1.0: return .green
        case 0.75..<0.9: return .blue
        case 0.5..<0.75: return .orange
        default: return .gray
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Empty State

private struct EmptyWisdomState: View {
    let canReceive: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            if canReceive {
                Text("No Recommendations Yet")
                    .font(.headline)
                Text("As the community grows, personalized insights will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Recommendations Disabled")
                    .font(.headline)
                Text("Enable recommendations in Settings to see community wisdom.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

#Preview {
    NavigationStack {
        WisdomFeedView()
            .environmentObject(WisdomService(supabase: DependencyContainer.shared.supabaseClient))
    }
}
