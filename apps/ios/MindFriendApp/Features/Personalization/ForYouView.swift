// ForYouView.swift
// Smart Personalization: Personalized content recommendations feed

import SwiftUI

struct ForYouView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var recommendations: [ContentRecommendation] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var currentMood: String?
    @State private var anxietyLevel: AnxietyLevel = .calm
    @State private var energyLevel: EnergyLevel = .moderate

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Mood Check
                    if currentMood == nil {
                        moodCheckSection
                    } else {
                        // Anxiety and Energy Levels
                        anxietyEnergySection
                    }

                    // Personalized Recommendations
                    if isLoading {
                        ProgressView("Loading personalized recommendations...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .accessibilityLabel("Loading recommendations")
                    } else if let error {
                        errorView(error)
                    } else if recommendations.isEmpty {
                        emptyStateView
                    } else {
                        recommendationsSection
                    }

                    // Quick Insights Preview
                    if !personalizationService.insights.isEmpty {
                        insightsPreviewSection
                    }
                }
                .padding()
            }
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task { await loadRecommendations() }
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh recommendations")
                }
            }
            .refreshable {
                await loadRecommendations()
            }
            .task {
                await loadRecommendations()
            }
        }
    }

    // MARK: - Anxiety & Energy Section

    private var anxietyEnergySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                // Anxiety Level
                VStack(alignment: .leading, spacing: 8) {
                    Label("Anxiety", systemImage: "brain.head.profile")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        ForEach(AnxietyLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation {
                                    anxietyLevel = level
                                }
                                Task { await loadRecommendations() }
                            } label: {
                                Image(systemName: level.icon)
                                    .foregroundStyle(anxietyLevel == level ? level.color : .gray)
                                    .font(.caption)
                            }
                            .accessibilityLabel("Anxiety: \(level.displayName)")
                        }
                    }
                }

                Spacer()

                // Energy Level
                VStack(alignment: .leading, spacing: 8) {
                    Label("Energy", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        ForEach(EnergyLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation {
                                    energyLevel = level
                                }
                                Task { await loadRecommendations() }
                            } label: {
                                Image(systemName: level.icon)
                                    .foregroundStyle(energyLevel == level ? level.color : .gray)
                                    .font(.caption)
                            }
                            .accessibilityLabel("Energy: \(level.displayName)")
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Mood Check Section

    private var moodCheckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling?")
                .font(.headline)

            Text("This helps us suggest the right content")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(["great", "good", "okay", "low", "stressed"], id: \.self) { mood in
                    Button {
                        withAnimation {
                            currentMood = mood
                        }
                        Task { await loadRecommendations() }
                    } label: {
                        VStack(spacing: 4) {
                            Text(moodEmoji(mood))
                                .font(.title)
                            Text(mood.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Feeling \(mood)")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recommended for You")
                    .font(.headline)

                Spacer()

                if currentMood != nil {
                    Button {
                        withAnimation {
                            currentMood = nil
                        }
                        Task { await loadRecommendations() }
                    } label: {
                        Text("Clear mood")
                            .font(.caption)
                    }
                }
            }

            ForEach(recommendations) { rec in
                RecommendationCard(recommendation: rec) {
                    Task {
                        try? await personalizationService.logRecommendationClick(contentId: rec.contentId)
                    }
                }
            }
        }
    }

    // MARK: - Insights Preview Section

    private var insightsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Insights")
                    .font(.headline)

                Spacer()

                NavigationLink {
                    PersonalizedInsightsView()
                        .environmentObject(container)
                } label: {
                    Text("See All")
                        .font(.subheadline)
                }
            }

            if let insight = personalizationService.insights.first {
                PersonalizedInsightCardCompact(insight: insight)
            }
        }
    }

    // MARK: - Empty & Error States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Your Personal Feed")
                .font(.headline)

            Text("Complete more activities to unlock personalized recommendations tailored just for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Unable to Load")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await loadRecommendations() }
            }, label: {
                Text("Try Again")
            })
            .buttonStyle(.bordered)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading recommendations")
        .accessibilityHint(message)
    }

    // MARK: - Helpers

    private func loadRecommendations() async {
        isLoading = true
        error = nil

        do {
            var context = RecommendationContext.current
            context.currentMood = currentMood
            context.anxietyLevel = anxietyLevel
            context.energyLevel = energyLevel

            recommendations = try await personalizationService.getRecommendations(
                contentType: "exercise",
                context: context
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func moodEmoji(_ mood: String) -> String {
        switch mood {
        case "great": return "😊"
        case "good": return "🙂"
        case "okay": return "😐"
        case "low": return "😔"
        case "stressed": return "😰"
        default: return "🙂"
        }
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: ContentRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Content preview placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 100)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: contentTypeIcon)
                                .font(.title)
                            Text(recommendation.contentType.capitalized)
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }

                // Recommendation reasons
                if !recommendation.reasons.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(recommendation.reasons.first ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Match score
                HStack {
                    ProgressView(value: recommendation.score)
                        .tint(scoreColor)

                    Text("\(Int(recommendation.score * 100))% match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recommendation.contentType.capitalized) recommendation, \(Int(recommendation.score * 100))% match")
    }

    private var contentTypeIcon: String {
        switch recommendation.contentType {
        case "audio": return "speaker.wave.2"
        case "visual": return "eye"
        case "exercise": return "figure.mind.and.body"
        case "micro_moment": return "sparkle"
        default: return "sparkles"
        }
    }

    private var scoreColor: Color {
        if recommendation.score >= 0.8 { return .green }
        if recommendation.score >= 0.5 { return .yellow }
        return .orange
    }
}

// MARK: - Compact Personalized Insight Card

struct PersonalizedInsightCardCompact: View {
    let insight: DBPersonalizedInsight

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title2)
                .foregroundStyle(insight.color)
                .frame(width: 40, height: 40)
                .background(insight.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ForYouView()
        .environmentObject(DependencyContainer())
}
