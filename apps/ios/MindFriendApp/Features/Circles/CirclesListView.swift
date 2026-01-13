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
            circles = try await container.circleService.getCircles()
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
                let circle = try await container.circleService.createCircle(
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
                let circle = try await container.circleService.joinCircle(inviteCode: inviteCode)
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

struct CircleDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    let circle: FriendCircle

    @State private var posts: [CirclePost] = []
    @State private var members: [CircleMember] = []
    @State private var isLoading = true
    @State private var showCheckin = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                CircleHeaderView(circle: circle, members: members)

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
                .padding(.horizontal)

                // Feed
                if posts.isEmpty {
                    EmptyFeedView()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Check-ins")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(posts) { post in
                            CirclePostRow(post: post)
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
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try await container.circleService.getCircle(id: circle.id)
            members = detail.members

            let to = Self.dateFormatter.string(from: Date())
            let from: String
            if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                from = Self.dateFormatter.string(from: weekAgo)
            } else {
                from = to
            }

            posts = try await container.circleService.getFeed(circleId: circle.id, from: from, to: to)
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
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
                let post = try await container.circleService.postCheckin(
                    circleId: circleId,
                    moodEmoji: selectedEmoji,
                    bodyText: bodyText.isEmpty ? nil : bodyText
                )
                await MainActor.run {
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
