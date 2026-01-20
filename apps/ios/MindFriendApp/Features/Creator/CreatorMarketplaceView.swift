// CreatorMarketplaceView.swift
// Browse and discover content creators

import SwiftUI

struct CreatorMarketplaceView: View {
    @EnvironmentObject var creatorService: CreatorService
    @State private var searchText = ""
    @State private var selectedCategory: ContentCategory?
    @State private var isLoading = false
    @State private var featuredCreators: [Creator] = []
    @State private var allCreators: [Creator] = []
    @State private var selectedCreator: Creator?

    private let categories: [ContentCategory] = [
        .all, .meditation, .breathing, .journaling, .movement, .educational
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search creators...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                CategoryPill(
                                    category: category,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = category
                                    Task { await loadCreators() }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Featured Creators Section
                    if !featuredCreators.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Featured Creators")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(featuredCreators) { creator in
                                        FeaturedCreatorCard(creator: creator)
                                            .onTapGesture {
                                                selectedCreator = creator
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Browse All Creators Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Browse Creators")
                                .font(.title2)
                                .fontWeight(.bold)

                            Spacer()

                            Text("\(filteredCreators.count) creators")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        LazyVStack(spacing: 12) {
                            ForEach(filteredCreators) { creator in
                                CreatorCard(creator: creator)
                                    .onTapGesture {
                                        selectedCreator = creator
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
            .navigationTitle("Discover")
            .task {
                await loadFeaturedCreators()
                await loadCreators()
            }
            .refreshable {
                await loadFeaturedCreators()
                await loadCreators()
            }
            .navigationDestination(item: $selectedCreator) { creator in
                PublicCreatorProfileView(creator: creator, creatorService: creatorService)
            }
        }
    }

    private var filteredCreators: [Creator] {
        var result = allCreators

        if !searchText.isEmpty {
            result = result.filter { creator in
                creator.displayName.localizedCaseInsensitiveContains(searchText) ||
                (creator.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    private func loadFeaturedCreators() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let creators = try await creatorService.browseCreators(limit: 10)
            featuredCreators = Array(creators.prefix(5))
        } catch {
            print("Failed to load featured creators: \(error)")
        }
    }

    private func loadCreators() async {
        isLoading = true
        defer { isLoading = false }

        do {
            allCreators = try await creatorService.browseCreators(limit: 50)
        } catch {
            print("Failed to load creators: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct CategoryPill: View {
    let category: ContentCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FeaturedCreatorCard: View {
    let creator: Creator

    var body: some View {
        VStack(spacing: 12) {
            // Profile Image
            Group {
                if let imageUrl = creator.profileImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            // Name
            Text(creator.displayName)
                .font(.headline)
                .lineLimit(1)

            // Verification Badge
            if creator.verificationLevel != .pending {
                Label(creator.verificationLevel.displayName, systemImage: creator.verificationLevel.badge)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            // Stats
            HStack(spacing: 12) {
                Label("\(creator.followerCount)", systemImage: "person.2")
                Label("\(creator.contentCount)", systemImage: "square.stack")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Rating
            if let rating = creator.averageRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .frame(width: 140)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct CreatorCard: View {
    let creator: Creator

    var body: some View {
        HStack(spacing: 16) {
            // Profile Image
            Group {
                if let imageUrl = creator.profileImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(creator.displayName)
                        .font(.headline)

                    if creator.verificationLevel != .pending {
                        Image(systemName: creator.verificationLevel.badge)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if let bio = creator.bio {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(creator.followerCount) followers", systemImage: "person.2")
                    Label("\(creator.contentCount) sessions", systemImage: "play.circle")

                    if let rating = creator.averageRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    CreatorMarketplaceView()
        .environmentObject(CreatorService(supabase: supabase))
}
