import SwiftUI

/// Filter options for micro-moment exercises
enum MicroMomentFilter: String, CaseIterable {
    case all = "All"
    case quick = "Quick (<30s)"
    case calming = "Calming"
    case energizing = "Energizing"

    func matches(_ template: MicroMomentTemplate) -> Bool {
        switch self {
        case .all:
            return true
        case .quick:
            return template.durationSeconds < 30
        case .calming:
            return template.energyEffect == .calming
        case .energizing:
            return template.energyEffect == .energizing
        }
    }
}

/// List view for browsing micro-moments by type
struct MicroMomentListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let type: MicroMomentType
    @ObservedObject var service: MicroMomentsService

    @State private var templates: [MicroMomentTemplate] = []
    @State private var selectedTemplate: MicroMomentTemplate?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFilter: MicroMomentFilter = .all

    /// Templates filtered by the selected filter
    private var filteredTemplates: [MicroMomentTemplate] {
        templates.filter { selectedFilter.matches($0) }
    }

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if templates.isEmpty {
                emptyView
            } else {
                templateList
            }
        }
        .supportScreen()
        .navigationTitle(type.displayName)
        .task {
            await loadTemplates()
        }
        .sheet(item: $selectedTemplate) { template in
            MicroMomentPlayerView(template: template) { completion in
                Task {
                    try? await service.recordCompletion(completion)
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
            Text("Loading exercises...")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.accent)

            Text("Couldn't load exercises")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await loadTemplates()
                }
            }
            .buttonStyle(.supportSecondary)
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: type.icon)
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.accent)

            Text("No \(type.displayName.lowercased()) exercises yet")
                .font(.headline)

            Text("Check back soon for new exercises")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Template List

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: SupportTheme.Spacing.m) {
                // Type header
                typeHeader

                // Filters
                filterSection

                // Template cards (filtered)
                ForEach(filteredTemplates) { template in
                    MicroMomentDetailCard(template: template) {
                        selectedTemplate = template
                    }
                }

                // Empty state when filter has no results
                if filteredTemplates.isEmpty && !templates.isEmpty {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundStyle(SupportTheme.textSecondary)

                        Text("No exercises match this filter")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)

                        Button("Clear Filter") {
                            selectedFilter = .all
                        }
                        .buttonStyle(.supportSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
    }

    private var typeHeader: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: type.icon)
                .font(.title)
                .foregroundStyle(SupportTheme.onAccent)
                .frame(width: 60, height: 60)
                .background(SupportTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(type.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                // Show filtered count if filter is active
                if selectedFilter == .all {
                    Text("\(templates.count) exercises available")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                } else {
                    Text("\(filteredTemplates.count) of \(templates.count) exercises")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.bottom, SupportTheme.Spacing.xs)
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(MicroMomentFilter.allCases, id: \.self) { filter in
                    MicroMomentFilterChip(
                        label: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
        .padding(.bottom, SupportTheme.Spacing.xs)
    }

    // MARK: - Data Loading

    private func loadTemplates() async {
        isLoading = true
        errorMessage = nil

        do {
            templates = try await service.fetchTemplates(type: type)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Filter Chip

struct MicroMomentFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.surface)
                .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Micro Moment Detail Card

struct MicroMomentDetailCard: View {
    let template: MicroMomentTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header
                HStack {
                    Image(systemName: template.type.icon)
                        .font(.title2)
                        .foregroundStyle(SupportTheme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(SupportTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        HStack {
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(SupportTheme.textPrimary)

                            if template.isPremium {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.accent)
                            }
                        }

                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Label(template.formattedDuration, systemImage: "clock")

                            if let effect = template.energyEffect {
                                Label(effect.displayName, systemImage: iconForEffect(effect))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(SupportTheme.accent)
                }

                // Description
                if let description = template.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Context tags
                if let contexts = template.suggestedContexts, !contexts.isEmpty {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        ForEach(contexts.prefix(3), id: \.self) { context in
                            Text(context.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.surface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .supportCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.title), \(template.formattedDuration)\(template.isPremium ? ", premium" : "")")
    }

    private func iconForEffect(_ effect: EnergyEffect) -> String {
        switch effect {
        case .calming: return "leaf"
        case .energizing: return "bolt"
        case .neutral: return "circle"
        }
    }
}

// MARK: - Preview

import Supabase

#Preview {
    NavigationStack {
        MicroMomentListView(
            type: .breathing,
            service: MicroMomentsService(supabase: SupabaseClient(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "example-key"
            ))
        )
    }
}
