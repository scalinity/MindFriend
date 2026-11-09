import SwiftUI

/// Main hub view for micro-moments feature
struct MicroMomentsHubView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var service: MicroMomentsService
    @State private var selectedTemplate: MicroMomentTemplate?
    @State private var showingBreathingExercise = false
    @State private var showingQuickCheckIn = false
    @State private var checkInType: CheckInType = .mood

    init(supabase: SupabaseClient) {
        _service = StateObject(wrappedValue: MicroMomentsService(supabase: supabase))
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Quick Actions
                    quickActionsSection

                    // Suggested Micro-Moments
                    if !service.suggestions.isEmpty {
                        suggestionsSection
                    }

                    // Practice totals
                    if let streak = service.streak, streak.totalMicroMoments > 0 {
                        practiceTotalsSection(streak)
                    }

                    // Browse by Type
                    browseSection

                    // Recent Activity
                    if !service.recentCompletions.isEmpty {
                        recentActivitySection
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle(SupportDestination.microMoments.title)
            .task {
                await service.loadData()
            }
            .refreshable {
                await service.loadData()
            }
            .sheet(item: $selectedTemplate) { template in
                MicroMomentPlayerView(template: template) { completion in
                    Task {
                        try? await service.recordCompletion(completion)
                    }
                }
            }
            .sheet(isPresented: $showingBreathingExercise) {
                QuickBreathingView { completion in
                    Task {
                        try? await service.recordCompletion(completion)
                    }
                }
            }
            .sheet(isPresented: $showingQuickCheckIn) {
                QuickCheckInSheet(type: checkInType) { checkIn in
                    Task {
                        try? await service.saveCheckIn(checkIn)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Quick Actions")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.s) {
                QuickActionButton(
                    icon: "wind",
                    title: "Breathe",
                    subtitle: "15 sec",
                    color: SupportTheme.accent
                ) {
                    showingBreathingExercise = true
                }

                QuickActionButton(
                    icon: "face.smiling",
                    title: "Mood",
                    subtitle: "2 taps",
                    color: SupportTheme.accent
                ) {
                    checkInType = .mood
                    showingQuickCheckIn = true
                }

                QuickActionButton(
                    icon: "bolt",
                    title: "Energy",
                    subtitle: "1 tap",
                    color: SupportTheme.accent
                ) {
                    checkInType = .energy
                    showingQuickCheckIn = true
                }

                QuickActionButton(
                    icon: "heart",
                    title: "Gratitude",
                    subtitle: "Quick",
                    color: SupportTheme.accent
                ) {
                    checkInType = .gratitude
                    showingQuickCheckIn = true
                }
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Suggested for You")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(service.suggestions) { template in
                MicroMomentCard(template: template) {
                    selectedTemplate = template
                }
            }
        }
    }

    // MARK: - Practice totals

    private func practiceTotalsSection(_ streak: MicroStreak) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Your Progress")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: SupportTheme.Spacing.m) {
                MicroMomentStatBox(
                    value: "\(streak.totalMicroMoments)",
                    label: "Moments",
                    icon: "sparkles",
                    color: SupportTheme.accent
                )

                MicroMomentStatBox(
                    value: "\(streak.totalMinutesPracticed)",
                    label: "Minutes",
                    icon: "clock.fill",
                    color: SupportTheme.accent
                )
            }
        }
    }

    // MARK: - Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Browse")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: SupportTheme.Spacing.s) {
                ForEach(MicroMomentType.allCases, id: \.self) { type in
                    NavigationLink {
                        MicroMomentListView(type: type, service: service)
                    } label: {
                        BrowseCategoryCard(type: type)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Recent")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(service.recentCompletions.prefix(3)) { completion in
                RecentCompletionRow(completion: completion, templates: service.templates)
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SupportTheme.Spacing.m)
            .background(SupportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

// MARK: - Micro Moment Card

struct MicroMomentCard: View {
    let template: MicroMomentTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.m) {
                Image(systemName: template.type.icon)
                    .font(.title2)
                    .foregroundStyle(SupportTheme.onAccent)
                    .frame(width: 50, height: 50)
                    .background(SupportTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text(template.formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if template.isPremium {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                    }
                }
            }
            .supportCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.title), \(template.formattedDuration)")
    }
}

// MARK: - Stat Box

struct MicroMomentStatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Browse Category Card

struct BrowseCategoryCard: View {
    let type: MicroMomentType

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: type.icon)
                .font(.title)
                .foregroundStyle(SupportTheme.accent)

            Text(type.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
        .accessibilityLabel(type.displayName)
    }
}

// MARK: - Recent Completion Row

struct RecentCompletionRow: View {
    let completion: MicroMomentCompletion
    let templates: [MicroMomentTemplate]

    private var template: MicroMomentTemplate? {
        templates.first { $0.id == completion.templateId }
    }

    var body: some View {
        HStack {
            if let template = template {
                Image(systemName: template.type.icon)
                    .foregroundStyle(SupportTheme.accent)

                Text(template.title)
                    .font(.subheadline)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(SupportTheme.accent)

                Text("Micro-moment")
                    .font(.subheadline)
            }

            Spacer()

            Text(completion.createdDate, style: .relative)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }
}

// MARK: - Preview

import Supabase

#Preview {
    MicroMomentsHubView(supabase: SupabaseClient(
        supabaseURL: URL(string: "https://example.supabase.co")!,
        supabaseKey: "example-key"
    ))
}
