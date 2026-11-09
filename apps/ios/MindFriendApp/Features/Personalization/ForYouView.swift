// ForYouView.swift
// Smart Personalization: Personalized content recommendations feed

import SwiftUI

struct ForYouView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @State private var recommendations: [ContentRecommendation] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var currentMood: String?
    @State private var anxietyLevel: AnxietyLevel = .calm
    @State private var energyLevel: EnergyLevel = .moderate
    @State private var exercises: [String: Exercise] = [:]

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
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
                            .padding(.vertical, SupportTheme.Spacing.xl)
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
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task { await loadRecommendations() }
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Stacked: each selector needs five 44-point targets, too wide to sit side by side on a phone.
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                // Anxiety Level
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Label("Anxiety", systemImage: "brain.head.profile")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        ForEach(AnxietyLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    anxietyLevel = level
                                }
                                Task { await loadRecommendations() }
                            } label: {
                                Image(systemName: level.icon)
                                    .foregroundStyle(anxietyLevel == level ? SupportTheme.accent : SupportTheme.textSecondary)
                                    .font(.caption)
                                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            }
                            .accessibilityLabel("Anxiety: \(level.displayName)")
                        }
                    }
                }

                // Energy Level
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Label("Energy", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        ForEach(EnergyLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    energyLevel = level
                                }
                                Task { await loadRecommendations() }
                            } label: {
                                Image(systemName: level.icon)
                                    .foregroundStyle(energyLevel == level ? SupportTheme.accent : SupportTheme.textSecondary)
                                    .font(.caption)
                                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            }
                            .accessibilityLabel("Energy: \(level.displayName)")
                        }
                    }
                }
            }
            .supportCard()
        }
    }

    // MARK: - Mood Check Section

    private var moodCheckSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("How are you feeling?")
                .font(.headline)

            Text("This helps us suggest the right content")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            HStack(spacing: SupportTheme.Spacing.m) {
                // Order: mood:1 (stressed) on left → mood:5 (great) on right
                ForEach(MoodEmojiMapper.moodsLowToHigh, id: \.name) { mood in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentMood = mood.name
                        }
                        Task { await loadRecommendations() }
                    } label: {
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Text(mood.emoji)
                                .font(.title)
                            Text(mood.name.capitalized)
                                .font(.caption2)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                    .accessibilityLabel("Feeling \(mood.name)")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .supportCard()
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            HStack {
                Text("Recommended for You")
                    .font(.headline)

                Spacer()

                if currentMood != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                if let exercise = findExercise(for: rec.contentId) {
                    NavigationLink {
                        LibraryExercisePlayerView(exercise: exercise, container: container)
                    } label: {
                        ContentRecommendationCardContent(recommendation: rec)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        Task {
                            try? await personalizationService.logRecommendationClick(contentId: rec.contentId)
                        }
                    })
                } else {
                    ContentRecommendationCardContent(recommendation: rec)
                        .opacity(0.6)
                }
            }
        }
    }

    // MARK: - Insights Preview Section

    private var insightsPreviewSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
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
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            Text("Your Personal Feed")
                .font(.headline)

            Text("Complete more activities to unlock personalized recommendations tailored just for you.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(SupportTheme.Spacing.m)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(.largeTitle))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Unable to Load")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await loadRecommendations() }
            }, label: {
                Text("Try Again")
            })
            .buttonStyle(.supportSecondary)
        }
        .padding(SupportTheme.Spacing.m)
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

            // Fetch exercises for navigation
            let fetchedExercises = try await container.supabaseDataService.getExercises()

            // Build map with normalized UUIDs as keys
            var exerciseMap: [String: Exercise] = [:]
            for exercise in fetchedExercises {
                let normalizedId = normalizeUUID(exercise.id)
                exerciseMap[normalizedId] = exercise
            }
            exercises = exerciseMap

            #if DEBUG
            print("DEBUG ForYouView: Fetched \(fetchedExercises.count) exercises, \(recommendations.count) recommendations")
            if let firstRec = recommendations.first {
                let found = exerciseMap[normalizeUUID(firstRec.contentId)] != nil
                print("DEBUG ForYouView: First recommendation lookup: \(found ? "FOUND" : "NOT FOUND")")
            }
            #endif
        } catch is CancellationError {
            // Task was cancelled (e.g., view disappeared or new refresh started)
            // Don't show this as an error to the user
            return // Don't update loading state, another task may be in progress
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Network request was cancelled
            return // Don't update loading state
        } catch {
            // Don't show "cancelled" errors from other sources
            let errorMessage = error.localizedDescription
            if !errorMessage.lowercased().contains("cancelled") && !errorMessage.lowercased().contains("canceled") {
                self.error = errorMessage
            }
        }

        isLoading = false
    }

    /// Normalize a UUID string to lowercase without hyphens for consistent comparison
    private func normalizeUUID(_ uuidString: String) -> String {
        // Remove hyphens and lowercase for consistent comparison
        return uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Find an exercise by contentId using normalized UUID comparison
    private func findExercise(for contentId: String) -> Exercise? {
        let normalizedContentId = normalizeUUID(contentId)
        return exercises[normalizedContentId]
    }
}

// MARK: - Recommendation Card Content

struct ContentRecommendationCardContent: View {
    let recommendation: ContentRecommendation

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            // Icon
            Image(systemName: contentTypeIcon)
                .font(.title)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 50, height: 50)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

            // Content
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(recommendation.contentName)
                    .font(.headline)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SupportTheme.Spacing.s) {
                    Label("\(recommendation.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text(recommendation.contentType.capitalized)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.surface)
                        .clipShape(Capsule())
                }

                // Recommendation reason
                if let reason = recommendation.reasons.first {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(reason)
                            .font(.caption)
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            // Match score and chevron
            HStack(spacing: SupportTheme.Spacing.xs) {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("\(Int(recommendation.score * 100))%")
                        .font(.headline)
                        .foregroundStyle(scoreColor)
                    Text("match")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recommendation.contentName), \(recommendation.durationMinutes) minutes, \(Int(recommendation.score * 100))% match")
    }

    private var contentTypeIcon: String {
        switch recommendation.contentType {
        case "breathing": return "wind"
        case "meditation": return "brain.head.profile"
        case "grounding": return "leaf.fill"
        case "journaling": return "pencil.line"
        case "movement": return "figure.walk"
        default: return "figure.mind.and.body"
        }
    }

    private var scoreColor: Color {
        if recommendation.score >= 0.8 { return SupportTheme.accent }
        if recommendation.score >= 0.5 { return SupportTheme.accent }
        return SupportTheme.accent
    }
}

// MARK: - Compact Personalized Insight Card

struct PersonalizedInsightCardCompact: View {
    let insight: DBPersonalizedInsight

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: insight.icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 40, height: 40)
                .background(SupportTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }
}

#Preview {
    ForYouView()
        .environmentObject(DependencyContainer())
}
