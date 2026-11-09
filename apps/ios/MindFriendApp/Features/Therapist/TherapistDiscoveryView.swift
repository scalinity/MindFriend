//
//  TherapistDiscoveryView.swift
//  MindFriendApp
//
//  Therapist/Coach Marketplace - Discovery View
//

import SwiftUI

struct TherapistDiscoveryView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = TherapistDiscoveryViewModel()

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Search and Filters
                    filterSection

                    // Loading State
                    if viewModel.isLoading && viewModel.therapists.isEmpty {
                        loadingView
                    } else if viewModel.showError {
                        SupportUnavailableState(title: "Support directory unavailable", message: viewModel.errorMessage, actionTitle: "Try again") {
                            viewModel.showError = false
                            Task { await viewModel.loadTherapists() }
                        }
                    } else if viewModel.therapists.isEmpty {
                        emptyStateView
                    } else {
                        // Results
                        therapistListSection
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle(SupportDestination.therapists.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TherapistApplicationView()
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .accessibilityLabel("Become a therapist or coach")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                }
            }
            .task {
                viewModel.therapistService = dependencies.therapistService
                await viewModel.loadTherapists()
            }
            .refreshable {
                await viewModel.loadTherapists()
            }

        }
    }

    // MARK: - Subviews

    private var filterSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Specialty Filter
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("What brings you here?")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(TherapistSpecialty.allCases.prefix(8), id: \.self) { specialty in
                            specialtyChip(specialty)
                        }
                    }
                }
            }

            // Profile Type Filter
            HStack(spacing: SupportTheme.Spacing.s) {
                profileTypeButton(nil, label: "All")
                profileTypeButton(.therapist, label: "Therapists")
                profileTypeButton(.coach, label: "Coaches")
            }

            // Sort Options
            HStack {
                Text("Sort by:")
                    .foregroundStyle(SupportTheme.textSecondary)

                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(TherapistSearchFilters.SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }
        }
    }

    private func specialtyChip(_ specialty: TherapistSpecialty) -> some View {
        Button {
            viewModel.toggleSpecialty(specialty)
        } label: {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: specialty.icon)
                    .font(.caption)
                Text(specialty.displayName)
                    .font(.subheadline)
            }
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(
                viewModel.selectedSpecialty == specialty
                    ? SupportTheme.accent
                    : SupportTheme.separator
            )
            .foregroundStyle(
                viewModel.selectedSpecialty == specialty
                    ? SupportTheme.onAccent
                    : .primary
            )
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(specialty.displayName), \(viewModel.selectedSpecialty == specialty ? "selected" : "not selected")")
    }

    private func profileTypeButton(_ type: TherapistProfileType?, label: String) -> some View {
        Button {
            viewModel.selectedProfileType = type
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(
                    viewModel.selectedProfileType == type
                        ? SupportTheme.accent
                        : SupportTheme.separator
                )
                .foregroundStyle(
                    viewModel.selectedProfileType == type
                        ? SupportTheme.onAccent
                        : .primary
                )
                .clipShape(Capsule())
        }
    }

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
            Text("Finding therapists...")
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "person.2.slash")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No therapists found")
                .font(.headline)

            Text("Try adjusting your filters or check back later.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Clear Filters") {
                viewModel.clearFilters()
            }
            .buttonStyle(.supportSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xl)
    }

    private var therapistListSection: some View {
        LazyVStack(spacing: SupportTheme.Spacing.m) {
            ForEach(viewModel.therapists) { therapist in
                NavigationLink {
                    TherapistProfileView(therapist: therapist)
                } label: {
                    TherapistCard(therapist: therapist)
                }
                .buttonStyle(.plain)
            }

            // Load More
            if viewModel.hasMore {
                Button {
                    Task {
                        await viewModel.loadMore()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Load More")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SupportTheme.Spacing.m)
            }
        }
    }
}

// MARK: - Therapist Card

struct TherapistCard: View {
    let therapist: TherapistProfile

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.m) {
                // Photo
                AsyncImage(url: URL(string: therapist.photoUrl ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                // Info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(therapist.displayName)
                            .font(.headline)

                        if therapist.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(SupportTheme.accent)
                                .font(.caption)
                                .accessibilityLabel("Verified")
                        }
                    }

                    Text(therapist.displayCredentials)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        // Rating
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(SupportTheme.accent)
                            Text(therapist.displayRating)
                            if therapist.ratingCount > 0 {
                                Text("(\(therapist.ratingCount))")
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                        .font(.caption)

                        Text("•")
                            .foregroundStyle(SupportTheme.textSecondary)

                        // Rate
                        Text(therapist.displayRate)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Specialties
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(therapist.displaySpecialties.prefix(4), id: \.self) { specialty in
                        Text(specialty.displayName)
                            .font(.caption)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.separator)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
    }
}

// MARK: - View Model

@MainActor
final class TherapistDiscoveryViewModel: ObservableObject {
    var therapistService: TherapistService?

    @Published var therapists: [TherapistProfile] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var hasMore = false

    @Published var selectedSpecialty: TherapistSpecialty? {
        didSet {
            scheduleFilteredLoad()
        }
    }

    @Published var selectedProfileType: TherapistProfileType? {
        didSet {
            scheduleFilteredLoad()
        }
    }

    @Published var sortOption: TherapistSearchFilters.SortOption = .ratingDescending {
        didSet {
            scheduleFilteredLoad()
        }
    }

    private var currentPage = 0
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    // MARK: - Private Helpers

    /// Schedules a debounced filter load, cancelling any pending search
    private func scheduleFilteredLoad() {
        // Cancel any in-flight search
        searchTask?.cancel()
        loadMoreTask?.cancel()

        // Debounce rapid filter changes (150ms delay)
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)

            guard !Task.isCancelled else { return }
            await loadTherapistsInternal()
        }
    }

    // MARK: - Public Methods

    func loadTherapists() async {
        // Cancel any pending operations
        searchTask?.cancel()
        loadMoreTask?.cancel()

        await loadTherapistsInternal()
    }

    private func loadTherapistsInternal() async {
        guard let service = therapistService else { return }

        isLoading = true
        currentPage = 0

        let filters = TherapistSearchFilters(
            specialty: selectedSpecialty,
            profileType: selectedProfileType,
            verifiedOnly: true,
            sortBy: sortOption,
            page: 0
        )

        do {
            let result = try await service.searchTherapists(filters: filters)

            // Check if task was cancelled before updating state
            guard !Task.isCancelled else { return }

            therapists = result.therapists
            hasMore = result.hasMore
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func loadMore() async {
        guard let service = therapistService, !isLoading, hasMore else { return }

        // Cancel any pending load more (shouldn't happen, but safety)
        loadMoreTask?.cancel()

        loadMoreTask = Task {
            isLoading = true
            currentPage += 1

            let filters = TherapistSearchFilters(
                specialty: selectedSpecialty,
                profileType: selectedProfileType,
                verifiedOnly: true,
                sortBy: sortOption,
                page: currentPage
            )

            do {
                let result = try await service.searchTherapists(filters: filters)

                guard !Task.isCancelled else {
                    currentPage -= 1
                    return
                }

                therapists.append(contentsOf: result.therapists)
                hasMore = result.hasMore
            } catch {
                guard !Task.isCancelled else {
                    currentPage -= 1
                    return
                }

                errorMessage = error.localizedDescription
                showError = true
                currentPage -= 1
            }

            isLoading = false
        }

        await loadMoreTask?.value
    }

    func toggleSpecialty(_ specialty: TherapistSpecialty) {
        if selectedSpecialty == specialty {
            selectedSpecialty = nil
        } else {
            selectedSpecialty = specialty
        }
    }

    func clearFilters() {
        // Cancel pending operations before clearing
        searchTask?.cancel()
        loadMoreTask?.cancel()

        // Set all at once to avoid multiple reloads
        selectedSpecialty = nil
        selectedProfileType = nil
        sortOption = .ratingDescending

        // Trigger single reload
        Task { await loadTherapists() }
    }

    deinit {
        searchTask?.cancel()
        loadMoreTask?.cancel()
    }
}

#Preview {
    TherapistDiscoveryView()
        .environmentObject(DependencyContainer.preview)
}
