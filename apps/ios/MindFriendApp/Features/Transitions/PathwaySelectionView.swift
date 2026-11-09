import SwiftUI

struct PathwaySelectionView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @State private var pathways: [TransitionPathway] = []
    @State private var selectedCategory: PathwayCategory? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPathway: TransitionPathway?

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach([nil] + PathwayCategory.allCases, id: \.self) { category in
                        PathwayCategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text(error)
                    .foregroundColor(.red)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: SupportTheme.Spacing.m) {
                        ForEach(filteredPathways) { pathway in
                            PathwayCard(pathway: pathway, isPremiumUser: appState.entitlements.tier == .premium)
                                .onTapGesture {
                                    if pathway.isPremium && appState.entitlements.tier != .premium {
                                        appState.showPaywall = true
                                    } else {
                                        selectedPathway = pathway
                                    }
                                }
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
        .supportScreen()
        .navigationTitle("Life Transitions")
        .sheet(item: $selectedPathway) { pathway in
            PathwayOnboardingFlow(pathway: pathway)
                .environmentObject(container)
        }
        .task {
            await loadPathways()
        }
    }

    var filteredPathways: [TransitionPathway] {
        if let category = selectedCategory {
            return pathways.filter { $0.category == category }
        }
        return pathways
    }

    func loadPathways() async {
        isLoading = true
        do {
            pathways = try await container.transitionService.fetchAvailablePathways(category: selectedCategory)
        } catch {
            errorMessage = "Failed to load pathways"
        }
        isLoading = false
    }
}

struct PathwayCategoryChip: View {
    let category: PathwayCategory?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category?.displayName ?? "All")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.2))
                .foregroundColor(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .cornerRadius(SupportTheme.cardRadius)
        }
    }
}

struct PathwayCard: View {
    let pathway: TransitionPathway
    var isPremiumUser: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: pathway.iconName)
                    .font(.title2)
                    .foregroundStyle(SupportTheme.accent)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(pathway.name)
                        .font(.headline)
                    Text("\(pathway.durationWeeks) weeks")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                if pathway.isPremium && !isPremiumUser {
                    Image(systemName: "crown.fill")
                        .foregroundColor(SupportTheme.accent)
                }
            }

            Text(pathway.description)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            HStack(spacing: SupportTheme.Spacing.xxs) {
                ForEach(pathway.phases) { phase in
                    Text(phase.name)
                        .font(.caption2)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.textSecondary.opacity(0.2))
                        .cornerRadius(SupportTheme.controlRadius)
                }
            }
        }
        .supportCard()
    }
}

// Color(hex:) extension already exists in AchievementsView.swift
