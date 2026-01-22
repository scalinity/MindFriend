//
//  BoundariesListView.swift
//  MindFriendApp
//
//  List view for all user's boundaries with filtering
//

import SwiftUI

struct BoundariesListView: View {
    @StateObject private var viewModel: BoundariesListViewModel
    @State private var showingNewBoundary = false

    init(service: BoundaryPlannerService) {
        _viewModel = StateObject(wrappedValue: BoundariesListViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.boundaries.isEmpty {
                    ProgressView()
                } else if viewModel.boundaries.isEmpty {
                    emptyState
                } else {
                    boundariesList
                }
            }
            .navigationTitle("list.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewBoundary = true
                    } label: {
                        Label("list.button_new", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    statusFilterMenu
                }
            }
            .sheet(isPresented: $showingNewBoundary) {
                NeedsAssessmentView(service: viewModel.service)
            }
            .task {
                await viewModel.loadBoundaries()
            }
            .refreshable {
                await viewModel.loadBoundaries()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("list.empty_state")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showingNewBoundary = true
            } label: {
                Label("list.button_new", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Boundaries List

    private var boundariesList: some View {
        List {
            ForEach(viewModel.boundaries) { boundary in
                NavigationLink {
                    BoundaryDetailView(boundaryId: boundary.id, service: viewModel.service)
                } label: {
                    BoundaryRowView(boundary: boundary)
                }
            }

            if viewModel.hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        await viewModel.loadMore()
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Status Filter Menu

    private var statusFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedFilter = "all"
                Task { await viewModel.loadBoundaries() }
            } label: {
                Label(
                    "list.filter_all",
                    systemImage: viewModel.selectedFilter == "all" ? "checkmark" : ""
                )
            }

            Button {
                viewModel.selectedFilter = "active"
                Task { await viewModel.loadBoundaries() }
            } label: {
                Label(
                    "list.filter_active",
                    systemImage: viewModel.selectedFilter == "active" ? "checkmark" : ""
                )
            }

            ForEach(BoundaryStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button {
                    viewModel.selectedFilter = status.rawValue
                    Task { await viewModel.loadBoundaries() }
                } label: {
                    Label(
                        status.displayName,
                        systemImage: viewModel.selectedFilter == status.rawValue ? "checkmark" : ""
                    )
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

// MARK: - Boundary Row View

struct BoundaryRowView: View {
    let boundary: BoundaryListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: boundary.boundaryType.icon)
                    .foregroundStyle(boundary.boundaryType.colorScheme)

                Text(boundary.statementText)
                    .font(.body)
                    .lineLimit(2)
            }

            HStack {
                StatusBadge(status: boundary.status)

                if boundary.practiceCount > 0 {
                    Text("\(boundary.practiceCount) practices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if boundary.hasFollowUp {
                    Label("list.has_followup", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(boundary.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: BoundaryStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

// MARK: - Boundary Detail View

struct BoundaryDetailView: View {
    @StateObject private var viewModel: BoundaryDetailViewModel

    let boundaryId: UUID
    let service: BoundaryPlannerService

    init(boundaryId: UUID, service: BoundaryPlannerService) {
        self.boundaryId = boundaryId
        self.service = service
        _viewModel = StateObject(wrappedValue: BoundaryDetailViewModel(service: service, boundaryId: boundaryId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let boundary = viewModel.boundary {
                detailContent(boundary)
            } else {
                ContentUnavailableView(
                    "detail.not_found_title",
                    systemImage: "exclamationmark.triangle",
                    description: Text("detail.not_found_description")
                )
            }
        }
        .navigationTitle("detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadBoundary()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("Retry") {
                Task { await viewModel.loadBoundary() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.showError = false
            }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ boundary: BoundaryListItem) -> some View {
        List {
            // Statement Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: boundary.boundaryType.icon)
                            .foregroundStyle(boundary.boundaryType.colorScheme)
                            .font(.title2)

                        Text(boundary.boundaryType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(boundary.statementText)
                        .font(.body)
                }
            } header: {
                Text("detail.statement_header")
            }

            // Why It Matters
            Section {
                Text(boundary.whyMatters ?? "")
                    .font(.body)
            } header: {
                Text("detail.why_matters_header")
            }

            // Status & Progress
            Section {
                HStack {
                    Text("detail.status")
                        .foregroundStyle(.secondary)

                    Spacer()

                    StatusBadge(status: boundary.status)
                }

                HStack {
                    Text("detail.practice_count")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(boundary.practiceCount)")
                        .fontWeight(.medium)
                }
            } header: {
                Text("detail.progress_header")
            }

            // Actions
            Section {
                NavigationLink {
                    ScriptGeneratorView(service: service, boundaryId: boundary.id)
                } label: {
                    Label("detail.action_scripts", systemImage: "text.bubble.fill")
                }

                NavigationLink {
                    BoundaryPracticeView(service: service, boundary: boundary)
                } label: {
                    Label("detail.action_practice", systemImage: "theatermasks.fill")
                }

                Button {
                    Task {
                        await viewModel.scheduleFollowUp()
                    }
                } label: {
                    HStack {
                        Label("detail.action_followup", systemImage: "calendar.badge.plus")

                        if viewModel.isSchedulingFollowUp {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isSchedulingFollowUp)
            } header: {
                Text("detail.actions_header")
            }
        }
    }
}

@MainActor
final class BoundaryDetailViewModel: ObservableObject {
    let service: BoundaryPlannerService
    let boundaryId: UUID

    @Published var boundary: BoundaryListItem?
    @Published var isLoading = false
    @Published var isSchedulingFollowUp = false
    @Published var error: Error?
    @Published var showError = false

    init(service: BoundaryPlannerService, boundaryId: UUID) {
        self.service = service
        self.boundaryId = boundaryId
    }

    func loadBoundary() async {
        isLoading = true
        error = nil

        do {
            let response = try await service.listBoundaries(limit: 100)
            boundary = response.boundaries.first { $0.id == boundaryId }
            
            if boundary == nil {
                error = NSError(domain: "BoundaryPlanner", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Boundary not found"
                ])
                showError = true
            }
        } catch {
            self.error = error
            self.showError = true
            print("Failed to load boundary: \(error)")
        }

        isLoading = false
    }

    func scheduleFollowUp() async {
        isSchedulingFollowUp = true
        error = nil

        do {
            _ = try await service.scheduleFollowUp(boundaryId: boundaryId)
        } catch {
            self.error = error
            self.showError = true
            print("Failed to schedule follow-up: \(error)")
        }

        isSchedulingFollowUp = false
    }
}

// MARK: - View Model

@MainActor
final class BoundariesListViewModel: ObservableObject {
    let service: BoundaryPlannerService

    @Published var boundaries: [BoundaryListItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedFilter = "all"

    private var currentOffset = 0
    private let pageSize = 20
    private var totalCount = 0

    var hasMore: Bool {
        boundaries.count < totalCount
    }

    init(service: BoundaryPlannerService) {
        self.service = service
    }

    func loadBoundaries() async {
        isLoading = true
        currentOffset = 0
        error = nil

        do {
            let response = try await service.listBoundaries(
                status: selectedFilter,
                limit: pageSize,
                offset: 0
            )

            boundaries = response.boundaries
            totalCount = response.total
            currentOffset = response.boundaries.count
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoading && hasMore else { return }

        isLoading = true

        do {
            let response = try await service.listBoundaries(
                status: selectedFilter,
                limit: pageSize,
                offset: currentOffset
            )

            boundaries.append(contentsOf: response.boundaries)
            currentOffset += response.boundaries.count
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

// MARK: - Previews

#Preview {
    BoundariesListView(service: BoundaryPlannerService(supabase: .mock))
}
