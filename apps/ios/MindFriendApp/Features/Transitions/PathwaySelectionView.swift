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
                HStack(spacing: 12) {
                    ForEach([nil] + PathwayCategory.allCases, id: \.self) { category in
                        PathwayCategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding()
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
                    LazyVStack(spacing: 16) {
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
                    .padding()
                }
            }
        }
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

struct PathwayCard: View {
    let pathway: TransitionPathway
    var isPremiumUser: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: pathway.iconName)
                    .font(.title2)
                    .foregroundColor(Color(hex: pathway.color))

                VStack(alignment: .leading, spacing: 4) {
                    Text(pathway.name)
                        .font(.headline)
                    Text("\(pathway.durationWeeks) weeks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if pathway.isPremium && !isPremiumUser {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                }
            }

            Text(pathway.description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(pathway.phases) { phase in
                    Text(phase.name)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Color(hex:) extension already exists in AchievementsView.swift
