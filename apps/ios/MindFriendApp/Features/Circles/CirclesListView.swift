import SwiftUI

struct CirclesListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var circles: [FriendCircle] = []
    @State private var isLoading = true
    @State private var showCreateCircle = false
    @State private var showJoinCircle = false
    @State private var loadError: String?

    // Circles tutorial state
    @AppStorage("circles_tutorial_completed") private var circlesTutorialCompleted = false
    @State private var showCirclesTutorial = false

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            Group {
                if isLoading {
                    ProgressView()
                } else if let loadError {
                    SupportUnavailableState(title: "Circles unavailable", message: loadError,
                        actionTitle: "Try Again", action: { Task { await loadCircles() } })
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
                        .listRowBackground(SupportTheme.surface)
                    }
                    .listRowBackground(SupportTheme.surface)
                    .listStyle(.plain)
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .accessibilityLabel("Create or join a circle")
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
            .onAppear {
                if !circlesTutorialCompleted {
                    showCirclesTutorial = true
                }
            }
            .fullScreenCover(isPresented: $showCirclesTutorial) {
                CirclesTutorialFlow(onComplete: {
                    circlesTutorialCompleted = true
                    showCirclesTutorial = false
                })
                .environmentObject(container)
            }
        }
    }

    private func loadCircles() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            circles = try await container.supabaseDataService.getCircles()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct CircleRow: View {
    let circle: FriendCircle

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            SupportRowLabel(title: circle.name, subtitle: "\(circle.memberCount) members", icon: "person.3.fill")

            Spacer()

            if circle.role == .owner {
                Image(systemName: "crown.fill")
                    .foregroundStyle(SupportTheme.Celebration.gold)
                    .accessibilityLabel("You are the owner")
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(circle.name), \(circle.memberCount) members\(circle.role == .owner ? ", you are the owner" : "")")
    }
}

struct EmptyCirclesView: View {
    @Binding var showCreate: Bool
    @Binding var showJoin: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(SupportTheme.textSecondary)

                Text("No circles yet")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.semibold)

                Text("Create a circle to share your wellness journey with friends")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Create", systemImage: "plus")
                            .padding(.horizontal, SupportTheme.Spacing.l)
                            .padding(.vertical, SupportTheme.Spacing.s)
                    }
                    .buttonStyle(.supportPrimary)

                    Button {
                        showJoin = true
                    } label: {
                        Label("Join", systemImage: "person.badge.plus")
                            .padding(.horizontal, SupportTheme.Spacing.l)
                            .padding(.vertical, SupportTheme.Spacing.s)
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
            .padding(SupportTheme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .supportField()
                        .lineLimit(2...4)
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    Text("Circles can have up to 8 members. You'll get an invite code to share with friends.")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .listRowBackground(SupportTheme.surface)
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Create Circle")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
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
            VStack(spacing: SupportTheme.Spacing.l) {
                Text("Enter the invite code shared by your friend")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)

                TextField("Invite Code", text: $inviteCode)

                    .supportField()
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
                .buttonStyle(.supportPrimary)
                .disabled(inviteCode.isEmpty || isJoining)

                Spacer()
            }
            .padding()
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Join Circle")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
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
    @State private var loadError: String?
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
            VStack(spacing: SupportTheme.Spacing.l) {
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
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Check-in button
                    Button {
                        showCheckin = true
                    } label: {
                        Label("Check In", systemImage: "hand.wave.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)

                    // Invite button
                    Button {
                        showInviteMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .accessibilityLabel("Invite a circle member")
                    .buttonStyle(.supportSecondary)
                }
                .padding(.horizontal)

                // Challenge creation (owner only)
                if circle.role == .owner && activeChallenge == nil {
                    Button {
                        showCreateChallenge = true
                    } label: {
                        HStack {
                            Image(systemName: "flag.fill")
                            Text("Create Challenge")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)
                    .padding(.horizontal)
                }

                // Members with hug buttons
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Members")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
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
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Recent Activity")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
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
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                    Button("Try Again") { Task { await loadData() } }
                        .buttonStyle(.supportSecondary)
                }
                .supportCard()
                .padding(SupportTheme.Spacing.m)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
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
                // Only open session view for active rituals (starting now)
                // Scheduled rituals shouldn't auto-open the session
                if ritual.status == .active {
                    selectedRitual = ritual
                } else {
                    // For scheduled rituals, just refresh the list to show the new ritual
                    Task {
                        await loadData()
                    }
                }
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
        loadError = nil
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
            loadError = error.localizedDescription
        }
    }
}

/// Member row with hug button
struct MemberRowWithHug: View {
    let member: CircleMember
    let circleId: String
    let isCurrentUser: Bool

    private static let avatarAreas: [SupportTheme.Area] = [.people, .journal, .voice, .quests, .insights, .exercises]

    /// Each member keeps one color across launches, taken from their user id.
    private var avatarPalette: AreaPalette {
        let seed = member.userId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.avatarAreas[seed % Self.avatarAreas.count].palette
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Avatar placeholder (CircleMember doesn't include avatarUrl)
            Circle()
                .fill(avatarPalette.tint)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(avatarPalette.ink)
                }
                .accessibilityLabel("\(member.displayName)'s profile picture")

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack(spacing: SupportTheme.Spacing.xxs) {
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
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                if member.role == .owner {
                    Text("Owner")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }

            Spacer()

            // Hug button (not for self)
            if !isCurrentUser {
                CompactHugButton(memberId: member.userId, circleId: circleId)
            }
        }
        .supportCard()
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                if isMilestone {
                    Text("🔥")
                        .font(.title)
                } else {
                    Text(post.moodEmoji ?? "👋")
                        .font(.title)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(post.userDisplayName)
                            .fontWeight(.semibold)

                        if isMilestone {
                            Text("MILESTONE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(SupportTheme.Area.quests.palette.ink)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.Area.quests.palette.tint)
                                .cornerRadius(SupportTheme.controlRadius)
                        }

                        Spacer()

                        Text(post.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    if let body = post.bodyText {
                        Text(body)
                            .font(.body)
                            .foregroundStyle(isMilestone ? SupportTheme.textPrimary : SupportTheme.textSecondary)
                    }
                }
            }

            // Reactions (show for all posts, especially milestones)
            ReactionDisplay(postId: post.id, reactions: $reactions)
                .padding(.leading, SupportTheme.Spacing.xl)
        }
        .padding()
        .background(isMilestone ? SupportTheme.Area.quests.palette.tint : SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
        .padding(.horizontal)
    }
}

struct CircleHeaderView: View {
    let circle: FriendCircle
    let members: [CircleMember]

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            if let desc = circle.description {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, SupportTheme.Spacing.s)
            }

            HStack {
                Label("\(circle.memberCount)/\(circle.maxMembers)", systemImage: "person.3.fill")
                Spacer()
                Text("Code: \(circle.inviteCode)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .font(.subheadline)
        }
        .supportCard()
        .padding(.horizontal)
    }
}

struct CirclePostRow: View {
    let post: CirclePost

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Text(post.moodEmoji ?? "👋")
                .font(.title)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack {
                    Text(post.userDisplayName)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                if let body = post.bodyText {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
        .padding(.horizontal)
    }
}

struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.textSecondary)
            Text("No check-ins yet")
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.vertical, SupportTheme.Spacing.xl)
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
            VStack(spacing: SupportTheme.Spacing.l) {
                Text("How are you feeling?")
                    .font(.headline)

                // Emoji picker
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: SupportTheme.Spacing.s) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 36))
                                .padding(SupportTheme.Spacing.xs)
                                .background(selectedEmoji == emoji ? SupportTheme.Area.people.palette.tint : Color.clear)
                                .cornerRadius(SupportTheme.controlRadius)
                        }
                    }
                }

                TextField("Share more (optional)", text: $bodyText, axis: .vertical)

                    .supportField()
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
                .background(SupportTheme.surface)
                .foregroundStyle(SupportTheme.textPrimary)
                .cornerRadius(SupportTheme.controlRadius)
                .disabled(isPosting)
            }
            .padding()
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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

                // Trigger XP gain toast IMMEDIATELY for instant gratification
                await MainActor.run {
                    container.achievementService.triggerXPGainAnimation(
                        amount: xpResult.amount,
                        activity: .circleCheckin
                    )
                }

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
