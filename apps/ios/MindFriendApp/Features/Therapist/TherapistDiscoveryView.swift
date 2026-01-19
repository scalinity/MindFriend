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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search and Filters
                    filterSection

                    // Loading State
                    if viewModel.isLoading && viewModel.therapists.isEmpty {
                        loadingView
                    } else if viewModel.therapists.isEmpty {
                        emptyStateView
                    } else {
                        // Results
                        therapistListSection
                    }
                }
                .padding()
            }
            .navigationTitle("Find Support")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TherapistApplicationView()
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .accessibilityLabel("Become a therapist or coach")
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Subviews

    private var filterSection: some View {
        VStack(spacing: 16) {
            // Specialty Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("What brings you here?")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TherapistSpecialty.allCases.prefix(8), id: \.self) { specialty in
                            specialtyChip(specialty)
                        }
                    }
                }
            }

            // Profile Type Filter
            HStack(spacing: 12) {
                profileTypeButton(nil, label: "All")
                profileTypeButton(.therapist, label: "Therapists")
                profileTypeButton(.coach, label: "Coaches")
            }

            // Sort Options
            HStack {
                Text("Sort by:")
                    .foregroundStyle(.secondary)

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
            HStack(spacing: 6) {
                Image(systemName: specialty.icon)
                    .font(.caption)
                Text(specialty.displayName)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                viewModel.selectedSpecialty == specialty
                    ? Color.accentColor
                    : Color(.systemGray6)
            )
            .foregroundStyle(
                viewModel.selectedSpecialty == specialty
                    ? .white
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    viewModel.selectedProfileType == type
                        ? Color.accentColor
                        : Color(.systemGray6)
                )
                .foregroundStyle(
                    viewModel.selectedProfileType == type
                        ? .white
                        : .primary
                )
                .clipShape(Capsule())
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Finding therapists...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No therapists found")
                .font(.headline)

            Text("Try adjusting your filters or check back later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Clear Filters") {
                viewModel.clearFilters()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var therapistListSection: some View {
        LazyVStack(spacing: 16) {
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
                .padding()
            }
        }
    }
}

// MARK: - Therapist Card

struct TherapistCard: View {
    let therapist: TherapistProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
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
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(therapist.displayName)
                            .font(.headline)

                        if therapist.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                                .accessibilityLabel("Verified")
                        }
                    }

                    Text(therapist.displayCredentials)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        // Rating
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(therapist.displayRating)
                            if therapist.ratingCount > 0 {
                                Text("(\(therapist.ratingCount))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)

                        Text("•")
                            .foregroundStyle(.secondary)

                        // Rate
                        Text(therapist.displayRate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }

            // Specialties
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(therapist.displaySpecialties.prefix(4), id: \.self) { specialty in
                        Text(specialty.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
