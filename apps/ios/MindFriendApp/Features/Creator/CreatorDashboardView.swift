// CreatorDashboardView.swift
// Main creator dashboard view with tabs for overview, content, earnings, and profile

import SwiftUI

struct CreatorDashboardView: View {
    @EnvironmentObject var creatorService: CreatorService
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            if let creator = creatorService.creatorProfile {
                TabView(selection: $selectedTab) {
                    // Overview Tab
                    ScrollView {
                        VStack(spacing: 20) {
                            // Stats Grid
                            LazyVGrid(columns: [GridItem(), GridItem()], spacing: 16) {
                                StatCard(
                                    title: "Total Plays",
                                    value: "\(creator.totalPlays)",
                                    icon: "play.circle",
                                    color: .blue
                                )

                                StatCard(
                                    title: "Followers",
                                    value: "\(creator.followerCount)",
                                    icon: "person.2",
                                    color: .purple
                                )

                                StatCard(
                                    title: "Content",
                                    value: "\(creator.contentCount)",
                                    icon: "square.stack",
                                    color: .green
                                )

                                StatCard(
                                    title: "Avg Rating",
                                    value: String(format: "%.1f", creator.averageRating ?? 0),
                                    icon: "star.fill",
                                    color: .yellow
                                )
                            }

                            // Earnings Summary
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Earnings")
                                    .font(.headline)

                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Pending")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("$\(String(format: "%.2f", creatorService.pendingEarnings))")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing) {
                                        Text("All Time")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("$\(String(format: "%.2f", creatorService.totalEarnings))")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding()
                    }
                    .tag(0)
                    .tabItem {
                        Label("Overview", systemImage: "chart.bar")
                    }

                    // Content Tab
                    ContentListView(creatorService: creatorService)
                        .tag(1)
                        .tabItem {
                            Label("Content", systemImage: "square.stack")
                        }

                    // Earnings Tab
                    EarningsView(creatorService: creatorService)
                        .tag(2)
                        .tabItem {
                            Label("Earnings", systemImage: "dollarsign.circle")
                        }

                    // Profile Tab
                    CreatorProfileEditView(creatorService: creatorService)
                        .tag(3)
                        .tabItem {
                            Label("Profile", systemImage: "person")
                        }
                }
                .navigationTitle("Creator Studio")
            } else {
                CreatorOnboardingView(creatorService: creatorService)
            }
        }
        .task {
            do {
                try await creatorService.loadCreatorProfile()
            } catch {
                // Profile loading failed - show onboarding instead
                Log.creative.error("Failed to load creator profile", error: error)
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ContentListView: View {
    @ObservedObject var creatorService: CreatorService
    @State private var showingNewContent = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(creatorService.myContent) { content in
                    NavigationLink {
                        ContentDetailView(content: content, creatorService: creatorService)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: content.contentType.icon)
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(content.title)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(content.contentType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                CreatorStatusBadge(status: content.status)

                                if content.status == .published {
                                    Text("\(content.playCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewContent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewContent) {
                NewContentView(creatorService: creatorService)
            }
        }
        .task {
            do {
                try await creatorService.loadMyContent()
            } catch {
                Log.creative.error("Failed to load content", error: error)
            }
        }
    }
}

struct EarningsView: View {
    @ObservedObject var creatorService: CreatorService

    var body: some View {
        NavigationStack {
            List {
                Section("Available for Payout") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("$\(String(format: "%.2f", creatorService.pendingEarnings))")
                                .font(.title)
                                .fontWeight(.bold)

                            if creatorService.pendingEarnings < 25 {
                                Text("Minimum $25 to request payout")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if creatorService.pendingEarnings >= 25 {
                            Button("Request Payout") {
                                // Handle payout request
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Section("Earnings History") {
                    ForEach(creatorService.earnings) { earning in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(earning.premiumMinutes) minutes played")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(earning.formattedNetEarnings)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text(earning.payoutStatus.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Earnings")
        }
        .task {
            do {
                try await creatorService.loadEarnings()
            } catch {
                Log.creative.error("Failed to load earnings", error: error)
            }
        }
    }
}

struct CreatorStatusBadge: View {
    let status: ContentStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.2))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

// MARK: - Creator Onboarding View

struct CreatorOnboardingView: View {
    @ObservedObject var creatorService: CreatorService
    @State private var showingApplication = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)

                Text("Become a Creator")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Share your wellness expertise and earn from your content")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Benefits
                VStack(alignment: .leading, spacing: 16) {
                    BenefitRow(
                        icon: "dollarsign.circle.fill",
                        title: "Earn Revenue",
                        description: "70% revenue share on premium content plays"
                    )
                    BenefitRow(
                        icon: "person.2.fill",
                        title: "Build Audience",
                        description: "Grow your follower base with discoverable content"
                    )
                    BenefitRow(
                        icon: "checkmark.seal.fill",
                        title: "Get Verified",
                        description: "Earn verification badges to build credibility"
                    )
                    BenefitRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Analytics Dashboard",
                        description: "Track plays, engagement, and earnings"
                    )
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Button {
                    showingApplication = true
                } label: {
                    Text("Apply Now")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Text("Application review takes 7 business days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 40)
            }
        }
        .sheet(isPresented: $showingApplication) {
            CreatorApplicationView(creatorService: creatorService)
        }
    }
}

struct CreatorProfileEditView: View {
    @ObservedObject var creatorService: CreatorService

    var body: some View {
        NavigationStack {
            List {
                if let creator = creatorService.creatorProfile {
                    Section("Profile") {
                        HStack {
                            if let imageUrl = creator.profileImageUrl, let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.gray)
                            }

                            VStack(alignment: .leading) {
                                Text(creator.displayName)
                                    .font(.headline)

                                if creator.verificationLevel != .pending {
                                    HStack(spacing: 4) {
                                        Image(systemName: creator.verificationLevel.badge)
                                            .font(.caption)
                                        Text(creator.verificationLevel.displayName)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    Section("Stats") {
                        HStack {
                            Text("Followers")
                            Spacer()
                            Text("\(creator.followerCount)")
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Content Published")
                            Spacer()
                            Text("\(creator.contentCount)")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct ContentDetailView: View {
    let content: CreatorContent
    @ObservedObject var creatorService: CreatorService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let mediaUrl = content.mediaUrl, let url = URL(string: mediaUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(content.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        Label(content.contentType.displayName, systemImage: content.contentType.icon)
                            .font(.caption)

                        Label(content.formattedDuration, systemImage: "clock")
                            .font(.caption)

                        if let rating = content.averageRating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .foregroundStyle(.secondary)

                    if let description = content.description {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Label("\(content.playCount)", systemImage: "play.circle")
                        Label("\(content.uniqueListeners)", systemImage: "person.2")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()

                Spacer()
            }
        }
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewContentView: View {
    @ObservedObject var creatorService: CreatorService
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var selectedType: ContentType = .meditation
    @State private var selectedFormat: ContentFormat = .audio
    @State private var selectedCategory = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Content Details") {
                    TextField("Title", text: $title)

                    Picker("Type", selection: $selectedType) {
                        ForEach(ContentType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Picker("Format", selection: $selectedFormat) {
                        Text("Audio").tag(ContentFormat.audio)
                        Text("Video").tag(ContentFormat.video)
                        Text("Text").tag(ContentFormat.text)
                    }
                }
            }
            .navigationTitle("New Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        Task {
                            _ = try? await creatorService.createContent(
                                title: title,
                                contentType: selectedType,
                                format: selectedFormat,
                                category: selectedCategory
                            )
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CreatorDashboardView()
        .environmentObject(CreatorService(supabase: supabase))
}
