import SwiftUI

/// Displays detected user patterns and behavioral insights from the Proactive Intelligence system
struct PatternsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var patterns: [UserPattern] = []
    @State private var engagementState: UserEngagementState?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.m) {
                if isLoading {
                    ProgressView("Analyzing your patterns...")
                        .frame(height: 200)
                } else if let error {
                    SupportUnavailableState(title: "Patterns unavailable", message: error, actionTitle: "Try again") {
                        Task { await loadData() }
                    }
                } else if patterns.isEmpty {
                    emptyStateView
                } else {
                    if let engagement = engagementState {
                        EngagementStateCard(state: engagement)
                    }

                    PatternsListView(
                        patterns: patterns,
                        onAcknowledge: acknowledgePattern
                    )
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Your Patterns")
        .background(SupportTheme.surface)
        .task { await loadData() }
        .refreshable { await loadData() }
        .trackScreen("patterns")
    }

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text("No Patterns Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Keep logging your moods, completing quests, and doing exercises. After about 2 weeks of data, MindFriend will start detecting patterns in your wellness journey.")
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.m)
        }
        .padding(SupportTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.cardRadius)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadData() async {
        isLoading = true
        error = nil

        do {
            async let patternsTask = container.supabaseDataService.getUserPatterns(activeOnly: true)
            async let engagementTask = container.supabaseDataService.getEngagementState()

            patterns = try await patternsTask
            engagementState = try await engagementTask
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func acknowledgePattern(_ pattern: UserPattern) {
        Task { @MainActor in
            do {
                try await container.supabaseDataService.acknowledgePattern(patternId: pattern.id)
                if let index = patterns.firstIndex(where: { $0.id == pattern.id }) {
                    let existing = patterns[index]
                    let updatedPattern = UserPattern(
                        id: existing.id,
                        userId: existing.userId,
                        patternType: existing.patternType,
                        patternKey: existing.patternKey,
                        patternData: existing.patternData,
                        confidence: existing.confidence,
                        firstDetectedAt: existing.firstDetectedAt,
                        lastConfirmedAt: existing.lastConfirmedAt,
                        timesSurfaced: existing.timesSurfaced,
                        userAcknowledged: true,
                        isActive: existing.isActive,
                        createdAt: existing.createdAt
                    )
                    patterns[index] = updatedPattern
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

// MARK: - Engagement State Card

struct EngagementStateCard: View {
    let state: UserEngagementState

    private var daysSinceLastActivity: Int {
        Calendar.current.dateComponents([.day], from: state.lastActivityAt, to: Date()).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Label("Engagement", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundColor(SupportTheme.Area.insights.palette.ink)
                Spacer()
                Text(state.currentState.displayName)
                    .font(.subheadline)
                    .foregroundColor(state.currentState.color)
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)
            }

            // Proactive engagement rate
            if state.proactiveMessageCount > 0 {
                HStack {
                    Text("Proactive engagement")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                    Spacer()
                    Text("\(Int(state.proactiveEngagementRate * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }

            // Mood decline indicator
            if state.moodDeclineDetected {
                HStack {
                    Image(systemName: "arrow.down.heart.fill")
                        .foregroundColor(SupportTheme.Status.caution)
                    Text("Recent mood decline detected")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.Status.caution)
                }
            }

            // Days since last activity
            if daysSinceLastActivity > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SupportTheme.Status.caution)
                    Text("\(daysSinceLastActivity) day\(daysSinceLastActivity > 1 ? "s" : "") since last check-in")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.Status.caution)
                }
            }
        }
        .supportCard()
    }
}

// MARK: - Patterns List View

struct PatternsListView: View {
    let patterns: [UserPattern]
    let onAcknowledge: (UserPattern) -> Void

    private var sortedPatterns: [UserPattern] {
        patterns.sorted { $0.confidence > $1.confidence }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Detected Patterns", systemImage: "wand.and.stars")
                .font(.headline)

            ForEach(sortedPatterns) { pattern in
                PatternCard(pattern: pattern, onAcknowledge: onAcknowledge)
            }
        }
    }
}

// MARK: - Pattern Card

struct PatternCard: View {
    let pattern: UserPattern
    let onAcknowledge: (UserPattern) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(alignment: .top) {
                Image(systemName: pattern.patternType.icon)
                    .font(.title2)
                    .foregroundColor(pattern.patternType.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(pattern.patternType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(SupportTheme.textSecondary)

                    Text(pattern.insightMessage ?? pattern.patternType.description)
                        .font(.body)
                }

                Spacer()
            }

            // Confidence indicator
            HStack {
                Text("Confidence")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(SupportTheme.textSecondary.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(confidenceColor)
                            .frame(width: geo.size.width * pattern.confidence, height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(Int(pattern.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            if !pattern.userAcknowledged {
                Button {
                    onAcknowledge(pattern)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Got it!")
                    }
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.accent)
                }
                .buttonStyle(.borderless)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SupportTheme.Status.positive)
                    Text("Acknowledged")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
    }

    private var confidenceColor: Color {
        if pattern.confidence >= 0.8 {
            return SupportTheme.Status.positive
        } else if pattern.confidence >= 0.6 {
            return SupportTheme.Status.caution
        } else {
            return SupportTheme.textSecondary
        }
    }
}

// MARK: - Pattern Type Extensions

extension PatternType {
    var color: Color {
        switch self {
        case .dayOfWeek:
            return SupportTheme.Area.voice.palette.ink
        case .exerciseCorrelation:
            return SupportTheme.Status.positive
        case .questPreference:
            return SupportTheme.Status.caution
        }
    }
}

// MARK: - Engagement State Extensions

extension EngagementState {
    var color: Color {
        switch self {
        case .highlyActive:
            return SupportTheme.Status.positive
        case .active:
            return SupportTheme.Area.voice.palette.ink
        case .moderate:
            return SupportTheme.Area.exercises.palette.ink
        case .drifting:
            return SupportTheme.Status.caution
        case .lapsed:
            return SupportTheme.Area.copingKits.palette.ink
        case .hibernating:
            return SupportTheme.textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PatternsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
