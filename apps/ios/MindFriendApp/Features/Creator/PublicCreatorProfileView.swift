// PublicCreatorProfileView.swift
// Public profile page for content creators

import SwiftUI

struct PublicCreatorProfileView: View {
    let creator: Creator
    @ObservedObject var creatorService: CreatorService

    @State private var content: [CreatorContent] = []
    @State private var isFollowing = false
    @State private var isLoading = false
    @State private var selectedContent: CreatorContent?
    @State private var showingSubscribeSheet = false
    @State private var subscriptionTier: SubscriptionTier = .monthly

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                VStack(spacing: 16) {
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
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())

                    // Name and Verification
                    HStack(spacing: 8) {
                        Text(creator.displayName)
                            .font(.title2)
                            .fontWeight(.bold)

                        if creator.verificationLevel != .pending {
                            Image(systemName: creator.verificationLevel.badge)
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                    }

                    // Stats Row
                    HStack(spacing: 24) {
                        StatItem(value: "\(creator.followerCount)", label: "Followers")
                        StatItem(value: "\(creator.contentCount)", label: "Sessions")
                        StatItem(value: formatMinutes(creator.totalMinutes), label: "Minutes")
                    }
                    .padding(.horizontal)

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await toggleFollow()
                            }
                        } label: {
                            HStack {
                                Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle")
                                Text(isFollowing ? "Following" : "Follow")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isFollowing ? Color.green.opacity(0.2) : Color.accentColor)
                            .foregroundStyle(isFollowing ? .green : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingSubscribeSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                Text("Subscribe")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // Rating
                    if let rating = creator.averageRating {
                        HStack(spacing: 4) {
                            ForEach(0..<5) { index in
                                Image(systemName: Double(index) < rating ? "star.fill" : (Double(index) < rating - 0.5 ? "star.leadinghalf.filled" : "star"))
                                    .foregroundStyle(.yellow)
                            }
                            Text(String(format: "%.1f", rating))
                                .fontWeight(.semibold)
                            Text("(\(creator.contentCount) sessions)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))

                // Bio Section
                if let bio = creator.bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.headline)

                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                }

                // Content Library Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Content Library")
                            .font(.headline)

                        Spacer()

                        Text("\(content.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    if content.isEmpty {
                        ContentUnavailableView(
                            "No Content Yet",
                            systemImage: "square.stack",
                            description: Text("This creator hasn't published any content yet.")
                        )
                        .frame(height: 200)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(content) { item in
                                ContentLibraryItem(
                                    content: item,
                                    onTap: {
                                        selectedContent = item
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Reviews Section (placeholder)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Reviews")
                            .font(.headline)

                        Spacer()

                        Button("See All") {
                            // Navigate to all reviews
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    // Sample reviews
                    VStack(spacing: 12) {
                        ReviewPreviewCard(
                            userName: "Sarah M.",
                            rating: 5,
                            preview: "This meditation session helped me sleep better than any medication..."
                        )
                        ReviewPreviewCard(
                            userName: "Michael R.",
                            rating: 4,
                            preview: "Great breathing exercises for anxiety. Would recommend!"
                        )
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle(creator.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadContent()
            isFollowing = creatorService.isFollowing(creator)
        }
        .navigationDestination(item: $selectedContent) { content in
            CreatorContentPlayerView(content: content, creatorService: creatorService)
        }
        .sheet(isPresented: $showingSubscribeSheet) {
            SubscribeSheetView(
                creator: creator,
                tier: $subscriptionTier,
                onSubscribe: {
                    showingSubscribeSheet = false
                    // Handle subscription
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            content = try await creatorService.getCreatorContent(creatorId: creator.id)
        } catch {
            print("Failed to load creator content: \(error)")
        }
    }

    private func toggleFollow() async {
        do {
            if isFollowing {
                try await creatorService.unfollowCreator(creator)
            } else {
                try await creatorService.followCreator(creator)
            }
            isFollowing.toggle()
        } catch {
            print("Failed to toggle follow: \(error)")
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ContentLibraryItem: View {
    let content: CreatorContent
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let imageUrl = content.coverImageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                    } else {
                        Color.gray.opacity(0.3)
                            .overlay {
                                Image(systemName: content.contentType.icon)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Label(content.contentType.displayName, systemImage: content.contentType.icon)
                        if let duration = content.durationSeconds {
                            Label(content.formattedDuration, systemImage: "clock")
                        }
                        if let rating = content.averageRating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct ReviewPreviewCard: View {
    let userName: String
    let rating: Int
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < rating ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(userName)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Text(preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SubscribeSheetView: View {
    let creator: Creator
    @Binding var tier: SubscriptionTier
    let onSubscribe: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Subscribe to \(creator.displayName)")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Get unlimited access to all sessions and exclusive content")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    ForEach([SubscriptionTier.monthly, .annual], id: \.self) { option in
                        Button {
                            tier = option
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(option.displayName)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text(option.displayPrice)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if tier == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.gray)
                                }
                            }
                            .padding()
                            .background(tier == option ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(tier == option ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: onSubscribe) {
                    Text("Subscribe - \(tier.displayPrice)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Dismiss handled by binding
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PublicCreatorProfileView(
            creator: Creator(
                id: UUID(),
                displayName: "Dr. Sarah Chen",
                bio: "Licensed clinical psychologist specializing in anxiety and mindfulness-based interventions. 15+ years of experience helping people find peace and purpose.",
                profileImageUrl: nil,
                websiteUrl: nil,
                verificationLevel: .verified,
                verifiedAt: Date(),
                status: .approved,
                followerCount: 12500,
                contentCount: 48,
                totalPlays: 125000,
                totalMinutes: 50000,
                averageRating: 4.8
            ),
            creatorService: CreatorService(supabase: supabase)
        )
    }
}
