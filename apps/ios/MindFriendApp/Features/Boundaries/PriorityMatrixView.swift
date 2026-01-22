//
//  PriorityMatrixView.swift
//  MindFriendApp
//
//  Visual display of identified needs from assessment with gap scores
//

import SwiftUI

struct PriorityMatrixView: View {
    let assessment: NeedsAssessment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("priority_matrix.title")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("priority_matrix.subtitle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Identified Needs
                VStack(alignment: .leading, spacing: 16) {
                    Text("priority_matrix.identified_needs_header")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(assessment.identifiedNeeds.sorted(by: { $0.gapScore > $1.gapScore })) { need in
                        NeedCard(need: need)
                            .padding(.horizontal)
                    }
                }

                // Boundary Recommendations
                if !assessment.boundaryRecommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("priority_matrix.recommendations_header")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(assessment.boundaryRecommendations) { recommendation in
                            RecommendationCard(recommendation: recommendation)
                                .padding(.horizontal)
                        }
                    }
                }

                // Next Steps
                VStack(alignment: .leading, spacing: 12) {
                    Text("priority_matrix.next_steps_header")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        NextStepCard(
                            title: "priority_matrix.next_step_define",
                            icon: "doc.text.fill",
                            description: "priority_matrix.next_step_define_description"
                        )

                        NextStepCard(
                            title: "priority_matrix.next_step_scripts",
                            icon: "text.bubble.fill",
                            description: "priority_matrix.next_step_scripts_description"
                        )

                        NextStepCard(
                            title: "priority_matrix.next_step_practice",
                            icon: "theatermasks.fill",
                            description: "priority_matrix.next_step_practice_description"
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("priority_matrix.navigation_title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Need Card

struct NeedCard: View {
    let need: IdentifiedNeed

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with gap score
            HStack {
                Text(need.needCategory)
                    .font(.headline)

                Spacer()

                Text("priority_matrix.gap_score \(need.gapScore)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(gapScoreColor(need.gapScore).opacity(0.2))
                    .foregroundStyle(gapScoreColor(need.gapScore))
                    .cornerRadius(8)
            }

            // Ratings
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("priority_matrix.importance")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        ForEach(0..<importanceLevelCount(need.importanceLevel), id: \.self) { _ in
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("priority_matrix.currently_met")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(need.currentlyMet)
                        .font(.body)
                        .fontWeight(.medium)
                }
            }

            // Why This Need
            if let whyMatters = need.whyMatters {
                Text(whyMatters)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func gapScoreColor(_ score: Int) -> Color {
        switch score {
        case 7...9: return .red
        case 4...6: return .orange
        default: return .yellow
        }
    }

    private func importanceLevelCount(_ level: String) -> Int {
        switch level {
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: BoundaryRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type badge
            HStack {
                Image(systemName: boundaryTypeIcon(recommendation.type))
                    .foregroundStyle(.accentColor)

                Text(recommendation.type)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Suggestion
            Text(recommendation.suggestion)
                .font(.body)
                .foregroundStyle(.primary)

            // Rationale
            Text(recommendation.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
    }

    private func boundaryTypeIcon(_ type: String) -> String {
        switch type {
        case "time": return "clock.fill"
        case "emotional": return "heart.fill"
        case "digital": return "iphone"
        case "physical": return "figure.stand"
        case "financial": return "dollarsign.circle.fill"
        default: return "shield.fill"
        }
    }
}

// MARK: - Next Step Card

struct NextStepCard: View {
    let title: LocalizedStringKey
    let icon: String
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        PriorityMatrixView(assessment: NeedsAssessment(
            id: UUID(),
            userId: UUID(),
            assessmentType: .work,
            responses: AssessmentResponses(
                step1DrainTriggers: ["work_stress"],
                step2ImportanceRatings: ["autonomy": .high, "rest": .medium],
                step3CurrentlyMet: ["autonomy": .no, "rest": .sometimes],
                step4PriorityNeeds: ["autonomy", "rest"]
            ),
            topNeeds: ["autonomy", "rest"],
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
}
