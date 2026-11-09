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
            LazyVStack(spacing: SupportTheme.Spacing.m) {
                if personalizationService.insights.isEmpty && !personalizationService.isLoading {
                    emptyState
                } else if personalizationService.isLoading {
                    ProgressView("Loading insights...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.xl)
                        .accessibilityLabel("Loading insights")
                } else {
                    ForEach(personalizationService.insights) { insight in
                        PersonalizedInsightCard(insight: insight)
                            .environmentObject(container)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
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
                    Group {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
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
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "lightbulb")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No Insights Yet")
                .font(.headline)

            Text("Keep using MindFriend and we'll discover patterns and suggestions tailored to you.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Generate Insights") {
                Task {
                    isRefreshing = true
                    try? await personalizationService.generateInsights()
                    isRefreshing = false
                }
            }
            .buttonStyle(.supportPrimary)
            .disabled(isRefreshing)
        }
        .padding(SupportTheme.Spacing.m)
    }
}

// MARK: - Personalized Insight Card

struct PersonalizedInsightCard: View {
    let insight: DBPersonalizedInsight
    @EnvironmentObject private var container: DependencyContainer

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundStyle(SupportTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(SupportTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                VStack(alignment: .leading) {
                    Text(insight.title)
                        .font(.headline)

                    Text(insight.insightCategory.capitalized)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
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
                        .foregroundStyle(SupportTheme.textSecondary)
                        .padding(SupportTheme.Spacing.xs)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("More options")
                }
            }

            Text(insight.description)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            // Confidence indicator
            HStack(spacing: SupportTheme.Spacing.xxs) {
                ConfidenceIndicator(confidence: insight.confidence)
                Text("\(Int(insight.confidence * 100))% confident")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            if let actionType = insight.actionTypeEnum {
                actionButton(for: actionType)
            }
        }
        .supportCard()
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
        .buttonStyle(.supportPrimary)
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
        HStack(spacing: SupportTheme.Spacing.xxs) {
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
            case 1: return SupportTheme.accent
            case 2: return SupportTheme.accent
            case 3: return SupportTheme.accent
            default: return SupportTheme.accent
            }
        }
        return SupportTheme.textSecondary.opacity(0.3)
    }
}

#Preview {
    NavigationStack {
        PersonalizedInsightsView()
            .environmentObject(DependencyContainer())
    }
}
