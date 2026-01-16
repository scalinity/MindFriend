// PersonalizedInsightsView.swift
// Smart Personalization: Display personalized insights and patterns

import SwiftUI

struct PersonalizedInsightsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var isRefreshing = false

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if personalizationService.insights.isEmpty && !personalizationService.isLoading {
                    emptyState
                } else if personalizationService.isLoading {
                    ProgressView("Loading insights...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .accessibilityLabel("Loading insights")
                } else {
                    ForEach(personalizationService.insights) { insight in
                        InsightCard(insight: insight)
                            .environmentObject(container)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        isRefreshing = true
                        try? await personalizationService.generateInsights()
                        isRefreshing = false
                    }
                }, label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                })
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh insights")
            }
        }
        .refreshable {
            try? await personalizationService.generateInsights()
        }
        .task {
            await personalizationService.loadInsights()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Insights Yet")
                .font(.headline)

            Text("Keep using MindFriend and we'll discover patterns and suggestions tailored to you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Generate Insights") {
                Task {
                    isRefreshing = true
                    try? await personalizationService.generateInsights()
                    isRefreshing = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .padding()
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: DBPersonalizedInsight
    @EnvironmentObject private var container: DependencyContainer

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundStyle(Color(insight.color))
                    .frame(width: 40, height: 40)
                    .background(Color(insight.color).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading) {
                    Text(insight.title)
                        .font(.headline)

                    Text(insight.insightCategory.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        Task {
                            try? await personalizationService.dismissInsight(insight)
                        }
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }

            Text(insight.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Confidence indicator
            HStack(spacing: 6) {
                ConfidenceIndicator(confidence: insight.confidence)
                Text("\(Int(insight.confidence * 100))% confident")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let actionType = insight.actionTypeEnum {
                actionButton(for: actionType)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            Task {
                try? await personalizationService.markInsightAsShown(insight)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.title). \(insight.description)")
    }

    @ViewBuilder
    private func actionButton(for actionType: InsightActionType) -> some View {
        Button {
            Task {
                try? await personalizationService.actOnInsight(insight)
            }
        } label: {
            HStack {
                Text(actionLabel(for: actionType))
                Image(systemName: "arrow.right")
            }
            .font(.subheadline)
            .fontWeight(.medium)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func actionLabel(for actionType: InsightActionType) -> String {
        switch actionType {
        case .tryContent: return "Try It"
        case .adjustSchedule: return "Update Schedule"
        case .setGoal: return "Set Goal"
        case .celebrate: return "Celebrate"
        case .adjustPreference: return "Update Preference"
        }
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: Double

    private var level: Int {
        if confidence < 0.4 { return 1 }
        if confidence < 0.7 { return 2 }
        return 3
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(fillColor(for: index))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Confidence level \(level) of 3")
    }

    private func fillColor(for index: Int) -> Color {
        if index < level {
            switch level {
            case 1: return .orange
            case 2: return .yellow
            case 3: return .green
            default: return .gray
            }
        }
        return .gray.opacity(0.3)
    }
}

#Preview {
    NavigationStack {
        PersonalizedInsightsView()
            .environmentObject(DependencyContainer())
    }
}
