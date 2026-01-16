import SwiftUI

/// Main hub view for micro-moments feature
struct MicroMomentsHubView: View {
    @StateObject private var service: MicroMomentsService
    @State private var selectedTemplate: MicroMomentTemplate?
    @State private var showingBreathingExercise = false
    @State private var showingQuickCheckIn = false
    @State private var checkInType: CheckInType = .mood

    init(supabase: SupabaseClient) {
        _service = StateObject(wrappedValue: MicroMomentsService(supabase: supabase))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Actions
                    quickActionsSection

                    // Suggested Micro-Moments
                    if !service.suggestions.isEmpty {
                        suggestionsSection
                    }

                    // Streak & Stats
                    if let streak = service.streak, streak.totalMicroMoments > 0 {
                        streakSection(streak)
                    }

                    // Browse by Type
                    browseSection

                    // Recent Activity
                    if !service.recentCompletions.isEmpty {
                        recentActivitySection
                    }
                }
                .padding()
            }
            .navigationTitle("Micro-Moments")
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "wind",
                    title: "Breathe",
                    subtitle: "15 sec",
                    color: .blue
                ) {
                    showingBreathingExercise = true
                }

                QuickActionButton(
                    icon: "face.smiling",
                    title: "Mood",
                    subtitle: "2 taps",
                    color: .orange
                ) {
                    checkInType = .mood
                    showingQuickCheckIn = true
                }

                QuickActionButton(
                    icon: "bolt",
                    title: "Energy",
                    subtitle: "1 tap",
                    color: .yellow
                ) {
                    checkInType = .energy
                    showingQuickCheckIn = true
                }

                QuickActionButton(
                    icon: "heart",
                    title: "Gratitude",
                    subtitle: "Quick",
                    color: .pink
                ) {
                    checkInType = .gratitude
                    showingQuickCheckIn = true
                }
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested for You")
                .font(.headline)

            ForEach(service.suggestions) { template in
                MicroMomentCard(template: template) {
                    selectedTemplate = template
                }
            }
        }
    }

    // MARK: - Streak

    private func streakSection(_ streak: MicroStreak) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress")
                .font(.headline)

            HStack(spacing: 16) {
                StatBox(
                    value: "\(streak.currentStreak)",
                    label: "Day Streak",
                    icon: "flame.fill",
                    color: .orange
                )

                StatBox(
                    value: "\(streak.totalMicroMoments)",
                    label: "Moments",
                    icon: "sparkles",
                    color: .purple
                )

                StatBox(
                    value: "\(streak.totalMinutesPracticed)",
                    label: "Minutes",
                    icon: "clock.fill",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

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
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            HStack(spacing: 16) {
                Image(systemName: template.type.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(template.type.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(template.formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    if template.isPremium {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.title), \(template.formattedDuration)")
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Browse Category Card

struct BrowseCategoryCard: View {
    let type: MicroMomentType

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title)
                .foregroundStyle(type.color)

            Text(type.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(template.type.color)

                Text(template.title)
                    .font(.subheadline)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)

                Text("Micro-moment")
                    .font(.subheadline)
            }

            Spacer()

            Text(completion.createdDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
