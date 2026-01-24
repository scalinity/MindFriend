import SwiftUI
import Supabase

/// Browse community strategies by category
struct StrategiesBrowserView: View {
    @EnvironmentObject private var wisdomService: WisdomService
    @State private var selectedCategory: StrategyCategory = .general
    @State private var showingContributeSheet = false
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Category Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StrategyCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                            Task {
                                try? await wisdomService.fetchStrategies(category: category)
                            }
                        }
                        .accessibilityLabel("\(category.displayName) category")
                        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Category filter")
            
            Divider()
            
            // Strategies List
            if wisdomService.isLoading && wisdomService.strategies.isEmpty {
                Spacer()
                ProgressView()
                    .accessibilityLabel("Loading strategies")
                Spacer()
            } else if wisdomService.strategies.isEmpty {
                EmptyStrategiesState(category: selectedCategory)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(wisdomService.strategies) { strategy in
                            StrategyDetailCard(
                                strategy: strategy,
                                onVote: { voteType in
                                    Task {
                                        try? await wisdomService.voteStrategy(
                                            strategyId: strategy.id,
                                            voteType: voteType
                                        )
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Community Strategies")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingContributeSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!wisdomService.canContribute)
                .accessibilityLabel("Share a new strategy")
            }
        }
        .sheet(isPresented: $showingContributeSheet) {
            ContributeStrategySheet(preselectedCategory: selectedCategory)
        }
        .task {
            try? await wisdomService.fetchStrategies(category: selectedCategory)
        }
        .refreshable {
            try? await wisdomService.fetchStrategies(category: selectedCategory)
        }
        .alert("Unable to Load", isPresented: $showingError) {
            Button("Retry") {
                Task {
                    try? await wisdomService.fetchStrategies(category: selectedCategory)
                }
            }
            Button("OK", role: .cancel) {
                wisdomService.clearError()
            }
        } message: {
            Text(wisdomService.error?.localizedDescription ?? "Please try again later.")
        }
        .onChange(of: wisdomService.error) { _, newError in
            showingError = newError != nil
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let category: StrategyCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Strategy Detail Card

private struct StrategyDetailCard: View {
    let strategy: CommunityStrategy
    let onVote: (VoteType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: strategy.category.iconName)
                    .foregroundColor(.accentColor)
                Text(strategy.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let context = strategy.transitionContext {
                    Text(context)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }

            // Strategy Text
            Text(strategy.strategyText)
                .font(.body)
                .lineSpacing(4)

            // Context
            if let context = strategy.context {
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(context)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Divider()

            // Stats and Actions
            HStack {
                // Stats
                HStack(spacing: 16) {
                    WisdomStatBadge(
                        icon: "hand.thumbsup.fill",
                        value: strategy.helpfulCount,
                        color: .green
                    )

                    if strategy.helpfulCount + strategy.notHelpfulCount > 0 {
                        Text("\(strategy.helpfulPercentage)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // Vote buttons
                HStack(spacing: 16) {
                    VoteButton(
                        icon: "hand.thumbsup",
                        filledIcon: "hand.thumbsup.fill",
                        isSelected: strategy.myVote == .helpful,
                        color: .green
                    ) {
                        onVote(.helpful)
                    }
                    .disabled(strategy.myVote != nil)

                    VoteButton(
                        icon: "hand.thumbsdown",
                        filledIcon: "hand.thumbsdown.fill",
                        isSelected: strategy.myVote == .notHelpful,
                        color: .red
                    ) {
                        onVote(.notHelpful)
                    }
                    .disabled(strategy.myVote != nil)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
}

// MARK: - Stat Badge

private struct WisdomStatBadge: View {
    let icon: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(value)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Vote Button

private struct VoteButton: View {
    let icon: String
    let filledIcon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? filledIcon : icon)
                .font(.title3)
                .foregroundColor(isSelected ? color : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

private struct EmptyStrategiesState: View {
    let category: StrategyCategory

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: category.iconName)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Strategies Yet")
                .font(.headline)

            Text("Be the first to share a \(category.displayName.lowercased()) strategy!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(40)
    }
}

#Preview {
    NavigationStack {
        StrategiesBrowserView()
            .environmentObject(WisdomService(supabase: DependencyContainer.shared.supabaseClient))
    }
}
