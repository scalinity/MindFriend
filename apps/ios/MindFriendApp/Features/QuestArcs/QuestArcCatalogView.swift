//
//  QuestArcCatalogView.swift
//  MindFriendApp
//
//  Quest Arc catalog for browsing and enrolling in multi-day programs
//

import SwiftUI

struct QuestArcCatalogView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var arcs: [QuestArc] = []
    @State private var selectedCategory: String? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedArc: QuestArc?
    @State private var activeArc: UserQuestArc?

    // Tutorial state
    @AppStorage("quest_journeys_tutorial_completed") private var tutorialCompleted = false
    @State private var showingTutorial = false

    private let categories = ["stress", "sleep", "confidence", "focus", "resilience"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Active Arc Banner (tappable to view details)
                    if let active = activeArc {
                        Button {
                            // Find the matching arc from the list or use the embedded one
                            if let matchingArc = arcs.first(where: { $0.id == active.arcId }) {
                                selectedArc = matchingArc
                            } else if let embeddedArc = active.questArc {
                                selectedArc = embeddedArc
                            }
                        } label: {
                            ActiveArcBanner(userArc: active)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Category Filter
                    categoryFilter

                    // Arc List
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = errorMessage {
                        errorView(error)
                    } else {
                        arcGrid
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Quest Journeys")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingTutorial = true
                        } label: {
                            Label("View Tutorial", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await loadArcs()
            }
            .task {
                await loadArcs()
            }
            .onAppear {
                if !tutorialCompleted {
                    showingTutorial = true
                }
            }
            .sheet(item: $selectedArc) { arc in
                QuestArcDetailView(arc: arc, activeArc: activeArc) {
                    await loadArcs()
                }
            }
            .fullScreenCover(isPresented: $showingTutorial) {
                QuestJourneysTutorialFlow {
                    tutorialCompleted = true
                    showingTutorial = false
                }
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                    Task { await loadArcs() }
                }

                ForEach(categories, id: \.self) { category in
                    CategoryChip(
                        title: category.capitalized,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                        Task { await loadArcs() }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var arcGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
            ForEach(filteredArcs) { arc in
                QuestArcCard(arc: arc, isEnrolled: activeArc?.arcId == arc.id) {
                    selectedArc = arc
                }
            }
        }
        .padding(.horizontal)
    }

    private var filteredArcs: [QuestArc] {
        if let category = selectedCategory {
            return arcs.filter { $0.category == category }
        }
        return arcs
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadArcs() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private func loadArcs() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Capture service reference to avoid retain cycle
            let service = container.questArcsService
            async let arcsTask = service.getQuestArcs(
                category: selectedCategory,
                includeCompleted: false
            )
            async let activeTask = service.getActiveArc()

            let (fetchedArcs, fetchedActive) = try await (arcsTask, activeTask)

            await MainActor.run {
                arcs = fetchedArcs
                activeArc = fetchedActive
                isLoading = false
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by a new refresh) - silently ignore
            await MainActor.run {
                isLoading = false
            }
        } catch {
            // Check if this is a URLSession cancellation error
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // Network request was cancelled - silently ignore
                await MainActor.run {
                    isLoading = false
                }
                return
            }

            // Also check for "cancelled" in error message (Supabase wraps cancellation errors)
            if error.localizedDescription.lowercased().contains("cancelled") ||
               error.localizedDescription.lowercased().contains("canceled") {
                await MainActor.run {
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Supporting Views

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

private struct QuestArcCard: View {
    let arc: QuestArc
    let isEnrolled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    categoryIcon
                    Spacer()
                    if arc.isPremium {
                        premiumBadge
                    }
                    if isEnrolled {
                        enrolledBadge
                    }
                }

                Text(arc.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(arc.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Label("\(arc.durationDays) days", systemImage: "calendar")
                    Spacer()
                    Label("\(arc.milestoneDays.count) milestones", systemImage: "flag.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var categoryIcon: some View {
        Image(systemName: QuestArcCategory.iconName(for: arc.category))
            .font(.title2)
            .foregroundStyle(QuestArcCategory.color(for: arc.category))
            .frame(width: 40, height: 40)
            .background(QuestArcCategory.color(for: arc.category).opacity(0.15))
            .clipShape(Circle())
    }

    private var premiumBadge: some View {
        Label("Premium", systemImage: "star.fill")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
    }

    private var enrolledBadge: some View {
        Label("Active", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .foregroundStyle(.green)
            .clipShape(Capsule())
    }
}

private struct ActiveArcBanner: View {
    let userArc: UserQuestArc

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("Active Journey")
                        .font(.headline)
                    Spacer()
                    Text("Day \(userArc.currentDay)/\(userArc.snapshotDurationDays)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let arc = userArc.questArc {
                    Text(arc.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: userArc.progressPercentage)
                    .tint(.orange)
            }

            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    QuestArcCatalogView()
        .environmentObject(DependencyContainer())
}
