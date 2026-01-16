import SwiftUI

/// List view for browsing micro-moments by type
struct MicroMomentListView: View {
    let type: MicroMomentType
    @ObservedObject var service: MicroMomentsService

    @State private var templates: [MicroMomentTemplate] = []
    @State private var selectedTemplate: MicroMomentTemplate?
    @State private var isLoading = true
    @State private var errorMessage: String?

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
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading exercises...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Couldn't load exercises")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await loadTemplates()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: type.icon)
                .font(.largeTitle)
                .foregroundStyle(type.color)

            Text("No \(type.displayName.lowercased()) exercises yet")
                .font(.headline)

            Text("Check back soon for new exercises")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Template List

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Type header
                typeHeader

                // Filters
                filterSection

                // Template cards
                ForEach(templates) { template in
                    MicroMomentDetailCard(template: template) {
                        selectedTemplate = template
                    }
                }
            }
            .padding()
        }
    }

    private var typeHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: type.icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(type.color)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(templates.count) exercises available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: true) {}

                FilterChip(label: "Quick (<30s)", isSelected: false) {}

                FilterChip(label: "Calming", isSelected: false) {}

                FilterChip(label: "Energizing", isSelected: false) {}
            }
        }
        .padding(.bottom, 8)
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

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
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
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: template.type.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(template.type.color)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if template.isPremium {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }

                        HStack(spacing: 8) {
                            Label(template.formattedDuration, systemImage: "clock")

                            if let effect = template.energyEffect {
                                Label(effect.displayName, systemImage: iconForEffect(effect))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(template.type.color)
                }

                // Description
                if let description = template.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Context tags
                if let contexts = template.suggestedContexts, !contexts.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(contexts.prefix(3), id: \.self) { context in
                            Text(context.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
