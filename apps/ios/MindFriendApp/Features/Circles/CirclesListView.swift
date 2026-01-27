import SwiftUI

struct CirclesListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var circles: [FriendCircle] = []
    @State private var isLoading = true
    @State private var showCreateCircle = false
    @State private var showJoinCircle = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if circles.isEmpty {
                    EmptyCirclesView(
                        showCreate: $showCreateCircle,
                        showJoin: $showJoinCircle
                    )
                } else {
                    List(circles) { circle in
                        NavigationLink {
                            CircleDetailView(circle: circle)
                        } label: {
                            CircleRow(circle: circle)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreateCircle = true
                        } label: {
                            Label("Create Circle", systemImage: "plus.circle")
                        }

                        Button {
                            showJoinCircle = true
                        } label: {
                            Label("Join Circle", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateCircle) {
                CreateCircleView { circle in
                    circles.append(circle)
                }
            }
            .sheet(isPresented: $showJoinCircle) {
                JoinCircleView { circle in
                    circles.append(circle)
                }
            }
            .refreshable {
                await loadCircles()
            }
            .task {
                await loadCircles()
            }
        }
    }

    private func loadCircles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            circles = try await container.supabaseDataService.getCircles()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

struct CircleRow: View {
    let circle: FriendCircle

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(circle.name)
                    .font(.headline)

                Text("\(circle.memberCount) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if circle.role == .owner {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("You are the owner")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(circle.name), \(circle.memberCount) members\(circle.role == .owner ? ", you are the owner" : "")")
    }
}

struct EmptyCirclesView: View {
    @Binding var showCreate: Bool
    @Binding var showJoin: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No circles yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a circle to share your wellness journey with friends")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 16) {
                Button {
                    showCreate = true
                } label: {
                    Label("Create", systemImage: "plus")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showJoin = true
                } label: {
                    Label("Join", systemImage: "person.badge.plus")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct CreateCircleView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    let onCreated: (FriendCircle) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Circle name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("Circles can have up to 8 members. You'll get an invite code to share with friends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createCircle()
                    }
                    .disabled(name.isEmpty || isCreating)
                }
            }
        }
    }

    private func createCircle() {
        isCreating = true
        Task {
            do {
                let circle = try await container.supabaseDataService.createCircle(
                    name: name,
                    description: description.isEmpty ? nil : description
                )
                await MainActor.run {
                    onCreated(circle)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
            isCreating = false
        }
    }
}

struct JoinCircleView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    let onJoined: (FriendCircle) -> Void

    @State private var inviteCode = ""
    @State private var isJoining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter the invite code shared by your friend")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Invite Code", text: $inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .font(.title2)
                    .multilineTextAlignment(.center)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    joinCircle()
                } label: {
                    if isJoining {
                        ProgressView()
                    } else {
                        Text("Join Circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteCode.isEmpty || isJoining)

                Spacer()
            }
            .padding()
            .navigationTitle("Join Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func joinCircle() {
        isJoining = true
        error = nil

        Task {
            do {
                let circle = try await container.supabaseDataService.joinCircle(inviteCode: inviteCode)
                await MainActor.run {
                    onJoined(circle)
                    dismiss()
                }
            } catch {
                self.error = "Invalid invite code or circle is full"
            }
            isJoining = false
        }
    }
}

// MARK: - Helper Functions

/// Safely parse circle ID to UUID with logging
/// Prevents silent data corruption from invalid UUIDs in the database
private func safeParseCircleUUID(_ idString: String, context: String) -> UUID {
    guard let uuid = UUID(uuidString: idString) else {
        print("⚠️ Invalid circle UUID in \(context): \(idString)")
        return UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
    }
    return uuid
}

struct CircleDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let circle: FriendCircle

    @State private var posts: [CirclePost] = []
    @State private var members: [CircleMember] = []
    @State private var activeChallenge: CircleChallenge?
    @State private var pendingInvites: [CircleInvite] = []
    @State private var postReactions: [String: [ReactionSummary]] = [:]
    @State private var isLoading = true
    @State private var showCheckin = false
    @State private var showCreateChallenge = false
    @State private var showInviteMember = false
    @State private var showCreateRitual = false
    @State private var selectedRitual: CircleRitual?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var currentUserId: String {
        appState.currentUser?.id.uuidString ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                CircleHeaderView(circle: circle, members: members)

                // Active Challenge
                if let challenge = activeChallenge {
                    ChallengeCard(
                        challenge: challenge,
                        members: members,
                        currentUserId: currentUserId
                    )
                    .padding(.horizontal)
                }

                // Rituals
                RitualScheduleCard(
                    circleId: safeParseCircleUUID(circle.id, context: "RitualScheduleCard"),
                    isOwner: circle.role == .owner,
                    onJoinRitual: { ritual in
                        selectedRitual = ritual
                    },
                    onCreateRitual: {
                        showCreateRitual = true
                    }
                )
                .padding(.horizontal)

                // Action buttons row
                HStack(spacing: 12) {
                    // Check-in button
                    Button {
                        showCheckin = true
                    } label: {
                        Label("Check In", systemImage: "hand.wave.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

                    // Invite button
                    Button {
                        showInviteMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                // Challenge creation (owner only)
                if circle.role == .owner && activeChallenge == nil {
                    Button {
                        showCreateChallenge = true
                    } label: {
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                            Text("Create Challenge")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                // Members with hug buttons
                VStack(alignment: .leading, spacing: 12) {
                    Text("Members")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(members) { member in
                        MemberRowWithHug(
                            member: member,
                            circleId: circle.id,
                            isCurrentUser: member.userId == currentUserId
                        )
                    }
                }

                // Pending invites
                PendingInvitesSection(invites: pendingInvites)

                // Feed
                if posts.isEmpty {
                    EmptyFeedView()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(posts) { post in
                            if post.kind == .ritualRecap {
                                RitualRecapCard(
                                    post: post,
                                    ritualId: post.ritualId.flatMap { UUID(uuidString: $0) }
                                )
                                .padding(.horizontal)
                            } else {
                                CirclePostRowWithReactions(
                                    post: post,
                                    reactions: Binding(
                                        get: { postReactions[post.id] ?? [] },
                                        set: { postReactions[post.id] = $0 }
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(circle.name)
        .sheet(isPresented: $showCheckin) {
            CircleCheckinView(circleId: circle.id) { post in
                posts.insert(post, at: 0)
            }
        }
        .sheet(isPresented: $showCreateChallenge) {
            CircleCreateChallengeSheet(circleId: circle.id) { challenge in
                activeChallenge = challenge
            }
        }
        .sheet(isPresented: $showInviteMember) {
            InviteMemberSheet(
                circleId: circle.id,
                circleName: circle.name,
                onInviteSent: { invite in
                    pendingInvites.insert(invite, at: 0)
                }
            )
        }
        .sheet(isPresented: $showCreateRitual) {
            CreateRitualSheet(circleId: safeParseCircleUUID(circle.id, context: "CreateRitualSheet")) { ritual in
                selectedRitual = ritual
            }
        }
        .fullScreenCover(item: $selectedRitual) { ritual in
            RitualSessionView(
                ritual: ritual,
                isCreator: ritual.createdBy == appState.currentUser?.id
            )
        }
        .refreshable {
            await loadData()
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load circle details and members
            let detail = try await container.supabaseDataService.getCircle(id: circle.id)
            members = detail.members

            // Load active challenge
            activeChallenge = try await container.supabaseDataService.getActiveChallenge(for: circle.id)

            // Load pending invites
            pendingInvites = try await container.supabaseDataService.getPendingInvites(for: circle.id)

            // Load feed
            let to = Self.dateFormatter.string(from: Date())
            let from: String
            if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                from = Self.dateFormatter.string(from: weekAgo)
            } else {
                from = to
            }
            posts = try await container.supabaseDataService.getCircleFeed(circleId: circle.id, from: from, to: to)

            // Batch load reactions for all posts (Fix 5: was N+1 query)
            let postIds = posts.map { $0.id }
            postReactions = try await container.supabaseDataService.getReactionsForPosts(postIds: postIds)
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

/// Member row with hug button
struct MemberRowWithHug: View {
    let member: CircleMember
    let circleId: String
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder (CircleMember doesn't include avatarUrl)
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("\(member.displayName)'s profile picture")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.displayName)
                        .fontWeight(.medium)

                    // Premium badge indicator
                    if let badgeIcon = member.premiumBadgeIcon {
                        Image(systemName: badgeIcon)
                            .font(.caption)
                            .foregroundStyle(member.premiumBadgeColor)
                    }

                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if member.role == .owner {
                    Text("Owner")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Hug button (not for self)
            if !isCurrentUser {
                CompactHugButton(memberId: member.userId, circleId: circleId)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

/// Post row with reactions
struct CirclePostRowWithReactions: View {
    let post: CirclePost
    @Binding var reactions: [ReactionSummary]

    var isMilestone: Bool {
        post.kind == .milestone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if isMilestone {
                    Text("🔥")
                        .font(.title)
                } else {
                    Text(post.moodEmoji ?? "👋")
                        .font(.title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(post.userDisplayName)
                            .fontWeight(.semibold)

                        if isMilestone {
                            Text("MILESTONE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                        }

                        Spacer()

                        Text(post.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let body = post.bodyText {
                        Text(body)
                            .font(.body)
                            .foregroundStyle(isMilestone ? .primary : .secondary)
                    }
                }
            }

            // Reactions (show for all posts, especially milestones)
            ReactionDisplay(postId: post.id, reactions: $reactions)
                .padding(.leading, 48)
        }
        .padding()
        .background(isMilestone ? Color.orange.opacity(0.05) : Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct CircleHeaderView: View {
    let circle: FriendCircle
    let members: [CircleMember]

    var body: some View {
        VStack(spacing: 16) {
            if let desc = circle.description {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Label("\(circle.memberCount)/\(circle.maxMembers)", systemImage: "person.3.fill")
                Spacer()
                Text("Code: \(circle.inviteCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct CirclePostRow: View {
    let post: CirclePost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(post.moodEmoji ?? "👋")
                .font(.title)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(post.userDisplayName)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let body = post.bodyText {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No check-ins yet")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }
}

struct CircleCheckinView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    let circleId: String
    let onPosted: (CirclePost) -> Void

    @State private var selectedEmoji = "🙂"
    @State private var bodyText = ""
    @State private var isPosting = false

    let emojis = ["😢", "😔", "😐", "🙂", "😊", "🎉", "💪", "🙏"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How are you feeling?")
                    .font(.headline)

                // Emoji picker
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 36))
                                .padding(8)
                                .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(12)
                        }
                    }
                }

                TextField("Share more (optional)", text: $bodyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Spacer()

                Button {
                    postCheckin()
                } label: {
                    if isPosting {
                        ProgressView()
                    } else {
                        Text("Share Check-in")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(isPosting)
            }
            .padding()
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func postCheckin() {
        isPosting = true
        Task {
            do {
                let post = try await container.supabaseDataService.postCheckin(
                    circleId: circleId,
                    moodEmoji: selectedEmoji,
                    bodyText: bodyText.isEmpty ? nil : bodyText
                )

                // Award XP for circle check-in
                let xpResult = try await container.supabaseDataService.awardXP(activity: .circleCheckin)

                await MainActor.run {
                    // Show level-up celebration if leveled up
                    if xpResult.leveledUp {
                        appState.showLevelUpCelebration(level: xpResult.newLevel, title: xpResult.newTitle)
                    }

                    onPosted(post)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
            isPosting = false
        }
    }
}

#Preview {
    CirclesListView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
