// Moderator Dashboard View - Review queue for moderators
// Per architect plan Phase E7: Pending reports, low confidence, crisis events tabs

import SwiftUI

struct ModeratorDashboardView: View {
    @StateObject private var viewModel: ModeratorDashboardViewModel
    @State private var selectedTab: ModeratorTab = .reports

    enum ModeratorTab: String, CaseIterable {
        case reports = "Pending Reports"
        case lowConfidence = "Low Confidence"
        case crisis = "Crisis Events"

        var icon: String {
            switch self {
            case .reports: return "exclamationmark.triangle"
            case .lowConfidence: return "questionmark.circle"
            case .crisis: return "heart.text.square"
            }
        }
    }

    init(forumService: ForumService) {
        _viewModel = StateObject(wrappedValue: ModeratorDashboardViewModel(forumService: forumService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Queue", selection: $selectedTab) {
                    ForEach(ModeratorTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                Group {
                    switch selectedTab {
                    case .reports:
                        reportsView
                    case .lowConfidence:
                        lowConfidenceView
                    case .crisis:
                        crisisView
                    }
                }
            }
            .navigationTitle("Moderator Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.refresh(tab: selectedTab)
            }
        }
        .task {
            await viewModel.loadInitial(tab: selectedTab)
        }
    }

    @ViewBuilder
    private var reportsView: some View {
        if viewModel.isLoading && viewModel.reports.isEmpty {
            ProgressView("Loading reports...")
        } else if viewModel.reports.isEmpty {
            ContentUnavailableView(
                "No Pending Reports",
                systemImage: "checkmark.circle",
                description: Text("All reports have been reviewed.")
            )
        } else {
            List(viewModel.reports) { report in
                ReportRowView(report: report)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var lowConfidenceView: some View {
        if viewModel.isLoading && viewModel.lowConfidenceThreads.isEmpty {
            ProgressView("Loading queue...")
        } else if viewModel.lowConfidenceThreads.isEmpty {
            ContentUnavailableView(
                "No Items in Queue",
                systemImage: "checkmark.circle",
                description: Text("All content has been reviewed.")
            )
        } else {
            List(viewModel.lowConfidenceThreads) { thread in
                VStack(alignment: .leading, spacing: 8) {
                    Text(thread.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Confidence: \(thread.moderationConfidence?.description ?? "N/A")")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(thread.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var crisisView: some View {
        if viewModel.isLoading && viewModel.crisisThreads.isEmpty {
            ProgressView("Loading crisis events...")
        } else if viewModel.crisisThreads.isEmpty {
            ContentUnavailableView(
                "No Crisis Events",
                systemImage: "checkmark.circle",
                description: Text("No crisis content detected recently.")
            )
        } else {
            List(viewModel.crisisThreads) { thread in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.red)
                        Text("CRISIS DETECTED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }

                    Text(thread.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(thread.createdAt.relativeTimeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(thread.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Report Row

struct ReportRowView: View {
    let report: ForumReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: reportIcon)
                    .foregroundStyle(reportColor)
                Text(report.reason.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if let details = report.details {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Reported \(report.createdAt.relativeTimeString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var reportIcon: String {
        switch report.reason {
        case .harassment: return "exclamationmark.triangle.fill"
        case .spam: return "trash.fill"
        case .misinformation: return "info.circle.fill"
        case .selfHarm: return "heart.text.square.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    private var reportColor: Color {
        switch report.reason {
        case .harassment: return .red
        case .spam: return .orange
        case .misinformation: return .yellow
        case .selfHarm: return .red
        case .other: return .gray
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ModeratorDashboardViewModel: ObservableObject {
    let forumService: ForumService

    @Published var reports: [ForumReport] = []
    @Published var lowConfidenceThreads: [ForumThread] = []
    @Published var crisisThreads: [ForumThread] = []
    @Published var isLoading = false

    init(forumService: ForumService) {
        self.forumService = forumService
    }

    func loadInitial(tab: ModeratorDashboardView.ModeratorTab) async {
        await load(tab: tab)
    }

    func refresh(tab: ModeratorDashboardView.ModeratorTab) async {
        await load(tab: tab)
    }

    private func load(tab: ModeratorDashboardView.ModeratorTab) async {
        isLoading = true

        do {
            switch tab {
            case .reports:
                reports = try await forumService.fetchPendingReports()
            case .lowConfidence:
                lowConfidenceThreads = try await forumService.fetchLowConfidenceQueue()
            case .crisis:
                crisisThreads = try await forumService.fetchCrisisEvents()
            }
        } catch {
            print("Error loading moderator queue:", error)
        }

        isLoading = false
    }
}
