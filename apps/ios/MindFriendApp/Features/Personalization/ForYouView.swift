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
    @State private var exercises: [String: Exercise] = [:]
    @State private var allExercises: [Exercise] = []

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

            // Fetch exercises for navigation
            let fetchedExercises = try await container.supabaseDataService.getExercises()
            self.allExercises = fetchedExercises
            print("DEBUG ForYouView: Fetched \(fetchedExercises.count) exercises")
            if let firstEx = fetchedExercises.first {
                print("DEBUG ForYouView: Sample exercise ID: '\(firstEx.id)'")
                print("DEBUG ForYouView: Normalized UUID: '\(normalizeUUID(firstEx.id))'")
            }

            // Build map with normalized UUIDs as keys
            var exerciseMap: [String: Exercise] = [:]
            for exercise in fetchedExercises {
                let normalizedId = normalizeUUID(exercise.id)
                exerciseMap[normalizedId] = exercise
            }
            exercises = exerciseMap

            // Debug: check if recommendations match
            print("DEBUG ForYouView: Exercise map has \(exerciseMap.count) entries")
            print("DEBUG ForYouView: Recommendations count: \(recommendations.count)")
            if let firstRec = recommendations.first {
                let normalizedContentId = normalizeUUID(firstRec.contentId)
                print("DEBUG ForYouView: Sample contentId: '\(firstRec.contentId)'")
                print("DEBUG ForYouView: Normalized contentId: '\(normalizedContentId)'")
                let found = exerciseMap[normalizedContentId] != nil
                print("DEBUG ForYouView: Lookup result: \(found ? "FOUND" : "NOT FOUND")")

                if !found {
                    // Print all exercise IDs to help debug
                    print("DEBUG ForYouView: All exercise normalized IDs:")
                    for (idx, ex) in fetchedExercises.prefix(5).enumerated() {
                        print("  [\(idx)] '\(normalizeUUID(ex.id))'")
                    }
                }
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., view disappeared or new refresh started)
            // Don't show this as an error to the user
            print("DEBUG ForYouView: Task cancelled")
            return // Don't update loading state, another task may be in progress
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Network request was cancelled
            print("DEBUG ForYouView: Network request cancelled")
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
        HStack(spacing: 16) {
            // Icon
            Image(systemName: contentTypeIcon)
                .font(.title)
                .foregroundStyle(.blue)
                .frame(width: 50, height: 50)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.contentName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(recommendation.durationMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(recommendation.contentType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }

                // Recommendation reason
                if let reason = recommendation.reasons.first {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(reason)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            // Match score and chevron
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text("\(Int(recommendation.score * 100))%")
                        .font(.headline)
                        .foregroundStyle(scoreColor)
                    Text("match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
