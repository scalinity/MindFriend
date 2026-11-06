import SwiftUI
import Supabase

/// Main hub view for peer support features
struct PeerSupportHubView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var service: PeerSupportService

    @State private var showRequestSupport = false
    @State private var showBecomeListener = false
    @State private var showShareWisdom = false

    init(supabase: SupabaseClient) {
        _service = StateObject(wrappedValue: PeerSupportService(supabase: supabase))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if service.isLoading {
                    loadingView
                } else {
                    // Request Support Card
                    requestSupportCard

                    // Active Sessions
                    if !service.activeSessions.isEmpty {
                        activeSessionsSection
                    }

                    // Mentorship Section
                    mentorshipSection

                    // Give Back Section
                    giveBackSection

                    // Listener Section
                    if service.listenerProfile == nil {
                        becomeListenerCard
                    } else {
                        listenerDashboardCard
                    }

                    // Community Wisdom Preview
                    if !service.communityWisdom.isEmpty {
                        communityWisdomSection
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Peer Support")
        .refreshable {
            await service.loadData()
        }
        .sheet(isPresented: $showRequestSupport) {
            RequestSupportSheet(service: service)
        }
        .sheet(isPresented: $showBecomeListener) {
            BecomeListenerView(service: service)
        }
        .sheet(isPresented: $showShareWisdom) {
            ShareWisdomSheet(service: service)
        }
        .task {
            await service.loadData()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading peer support...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Request Support Card

    private var requestSupportCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue.gradient)

            Text("Need Someone to Talk To?")
                .font(.title3.bold())

            Text("Connect with a trained peer supporter for a confidential conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showRequestSupport = true
            } label: {
                Label("Request Support", systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Request peer support")
        .accessibilityHint("Opens a form to request a support session")
    }

    // MARK: - Active Sessions Section

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Sessions")
                .font(.headline)

            ForEach(service.activeSessions) { session in
                NavigationLink {
                    SupportSessionView(session: session, service: service)
                } label: {
                    ActiveSessionCard(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mentorship Section
    // TODO: Re-enable after fixing Mentorship module

    private var mentorshipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mentorship")
                .font(.headline)

            // Existing mentorships (legacy system)
            if service.mentorships.isEmpty {
                MentorshipEmptyCard()
            } else {
                ForEach(service.mentorships) { mentorship in
                    NavigationLink {
                        MentorshipDetailView(mentorship: mentorship, service: service)
                    } label: {
                        MentorshipCard(mentorship: mentorship)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Give Back Section

    private var giveBackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give Back")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                GiveBackOption(
                    icon: "hands.sparkles.fill",
                    title: "Send Hugs",
                    color: .pink
                ) {
                    // Navigate to send hugs - could show a sheet
                }

                GiveBackOption(
                    icon: "lightbulb.fill",
                    title: "Share Wisdom",
                    color: .yellow
                ) {
                    showShareWisdom = true
                }

                NavigationLink {
                    GratitudeWallView(service: service)
                } label: {
                    GiveBackOptionContent(
                        icon: "star.fill",
                        title: "Gratitude Wall",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CommunityWisdomView(service: service)
                } label: {
                    GiveBackOptionContent(
                        icon: "book.fill",
                        title: "Browse Wisdom",
                        color: .purple
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Become Listener Card

    private var becomeListenerCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.green.gradient)

            Text("Become a Listener")
                .font(.title3.bold())

            Text("Help others by becoming a trained peer supporter. Give back to the community and grow through service.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showBecomeListener = true
            } label: {
                Label("Learn More", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Become a peer listener")
        .accessibilityHint("Opens information about becoming a trained peer supporter")
    }

    // MARK: - Listener Dashboard Card

    private var listenerDashboardCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: listenerStatusIcon)
                    .foregroundStyle(listenerStatusColor)
                Text(listenerStatusText)
                    .font(.headline)
                Spacer()

                if service.listenerProfile?.status == .active {
                    Toggle("", isOn: Binding(
                        get: { service.listenerProfile?.isAvailable ?? false },
                        set: { newValue in
                            Task {
                                try? await service.toggleListenerAvailability(isAvailable: newValue)
                            }
                        }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Availability toggle")
                    .accessibilityValue(service.listenerProfile?.isAvailable == true ? "Available" : "Unavailable")
                }
            }

            if let listener = service.listenerProfile, listener.status == .active {
                HStack(spacing: 20) {
                    ListenerStat(
                        value: "\(listener.totalSessions)",
                        label: "Sessions"
                    )
                    ListenerStat(
                        value: String(format: "%.1f", listener.averageRating ?? 0),
                        label: "Rating"
                    )
                    ListenerStat(
                        value: String(format: "%.0fh", listener.totalHours),
                        label: "Hours"
                    )
                }
            }

            NavigationLink {
                if let listener = service.listenerProfile {
                    ListenerDashboardView(listener: listener, service: service)
                }
            } label: {
                Text("View Dashboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(service.listenerProfile == nil)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var listenerStatusIcon: String {
        switch service.listenerProfile?.status {
        case .active:
            return "checkmark.seal.fill"
        case .training:
            return "book.fill"
        case .applicant:
            return "clock.fill"
        case .inactive:
            return "pause.circle.fill"
        case .suspended, .none:
            return "exclamationmark.triangle.fill"
        }
    }

    private var listenerStatusColor: Color {
        switch service.listenerProfile?.status {
        case .active:
            return .green
        case .training:
            return .blue
        case .applicant:
            return .orange
        case .inactive:
            return .gray
        case .suspended, .none:
            return .red
        }
    }

    private var listenerStatusText: String {
        switch service.listenerProfile?.status {
        case .active:
            return "Certified Listener"
        case .training:
            return "In Training"
        case .applicant:
            return "Application Pending"
        case .inactive:
            return "Inactive"
        case .suspended:
            return "Suspended"
        case .none:
            return "Not a Listener"
        }
    }

    // MARK: - Community Wisdom Section

    private var communityWisdomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Community Wisdom")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    CommunityWisdomView(service: service)
                }
                .font(.subheadline)
            }

            ForEach(service.communityWisdom.prefix(3)) { wisdom in
                WisdomCard(wisdom: wisdom)
            }
        }
    }
}

// MARK: - Supporting Views

struct ActiveSessionCard: View {
    let session: DBSupportSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionType.displayName)
                    .font(.subheadline.bold())
                Text(session.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.status == .active {
                Text("In Progress")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else if session.status == .pending {
                Text("Waiting")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.sessionType.displayName) session, \(session.status.displayName)")
    }
}

struct GiveBackOption: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GiveBackOptionContent(icon: icon, title: title, color: color)
        }
        .buttonStyle(.plain)
    }
}

struct GiveBackOptionContent: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct ListenerStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct MentorshipEmptyCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No active mentorships")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Find a mentor who has navigated similar challenges")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MentorshipCard: View {
    let mentorship: DBMentorship

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mentorship")
                    .font(.subheadline.bold())
                Text(mentorship.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let challenges = mentorship.matchedOnChallenges, !challenges.isEmpty {
                    Text(challenges.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let nextCheckin = mentorship.nextCheckinDue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next check-in")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(nextCheckin, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WisdomCard: View {
    let wisdom: DBCommunityWisdom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: wisdom.category.icon)
                    .foregroundStyle(.yellow)
                Text(wisdom.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "hand.thumbsup")
                        .font(.caption)
                    Text("\(wisdom.helpfulCount)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Text(wisdom.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Placeholder Views

struct SupportSessionView: View {
    @ObservedObject var service: PeerSupportService
    @State private var session: DBSupportSession
    @State private var messages: [DBSupportMessage] = []
    @State private var myRole: DBSupportMessage.SenderType?
    @State private var draft = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showEndConfirmation = false
    @State private var revision = 0

    init(session: DBSupportSession, service: PeerSupportService) {
        _session = State(initialValue: session)
        self.service = service
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(session.status.displayName, systemImage: session.sessionType.icon)
                Spacer()
                if isBusy { ProgressView() }
            }
            .font(.subheadline).padding()
            .background(Color(.secondarySystemBackground))

            if let errorMessage {
                HStack(alignment: .top) {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { Task { await refresh() } }.font(.caption)
                }.padding(.horizontal).padding(.vertical, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            Text(session.status == .active ? "Your conversation can begin here." : "Messages will appear when the conversation begins.")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 32)
                        }
                        ForEach(messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }.padding()
                }
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            if session.status == .active {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Message to your support partner")
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(isBusy || myRole == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            } else if session.status == .matched || session.status == .pending {
                VStack(spacing: 12) {
                    if session.status == .matched && myRole == .listener {
                        Button("Begin Conversation") { Task { await begin() } }.buttonStyle(.borderedProminent)
                    } else {
                        Text(session.status == .pending ? "Waiting for an available peer listener." : "Your listener will begin the conversation shortly.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("Cancel Request", role: .destructive) { Task { await cancel() } }
                }.padding().disabled(isBusy || myRole == nil)
            } else {
                Text("This conversation has ended.").font(.subheadline).foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle("Peer Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.status == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", role: .destructive) { showEndConfirmation = true }.disabled(isBusy)
                }
            }
        }
        .confirmationDialog("End this support session?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { Task { await end() } }
            Button("Keep Talking", role: .cancel) { }
        }
        .onReceive(service.$currentSessionMessages) { mergeMessages($0) }
        .task(id: session.id) {
            await refresh()
            guard !Task.isCancelled else { return }
            var subscriptionId: UUID?
            if session.status.isActive {
                do { subscriptionId = try await service.subscribeToSessionMessages(sessionId: session.id) }
                catch is CancellationError { return }
                catch { errorMessage = "Live updates are unavailable. Messages will refresh automatically." }
            }
            while !Task.isCancelled && session.status.isActive {
                if !isBusy { await refresh() }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
            if let subscriptionId { await service.unsubscribeFromSessionMessages(subscriptionId: subscriptionId) }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: DBSupportMessage) -> some View {
        if message.senderType == .system {
            Text(message.content).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        } else {
            let isMine = message.senderType == myRole
            HStack {
                if isMine { Spacer(minLength: 40) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    Text(isMine ? "You" : message.senderType == .listener ? "Listener" : "Support partner")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(message.content).textSelection(.enabled)
                        .padding(12)
                        .background(isMine ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                if !isMine { Spacer(minLength: 40) }
            }
        }
    }

    private func mergeMessages(_ incoming: [DBSupportMessage]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in incoming where message.sessionId == session.id { byId[message.id] = message }
        messages = byId.values.sorted { $0.sentAt == $1.sentAt ? $0.id.uuidString < $1.id.uuidString : $0.sentAt < $1.sentAt }
    }

    private func refresh() async {
        let startedRevision = revision
        do {
            let saved = try await service.fetchSession(sessionId: session.id)
            let role = try await service.participantType(for: saved)
            let savedMessages = try await service.fetchSessionMessages(sessionId: session.id)
            try Task.checkCancellation()
            guard revision == startedRevision else { return }
            session = saved
            myRole = role
            mergeMessages(savedMessages)
            errorMessage = nil
        } catch is CancellationError { } catch PeerSupportError.notAuthenticated {
            messages = []; myRole = nil; errorMessage = PeerSupportError.notAuthenticated.localizedDescription
        } catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        guard !isBusy else { return }
        let capturedDraft = draft
        isBusy = true
        defer { isBusy = false }
        do {
            let saved = try await service.sendMessage(sessionId: session.id, content: capturedDraft)
            mergeMessages([saved])
            if draft == capturedDraft { draft = "" }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func begin() async {
        guard !isBusy else { return }
        isBusy = true; revision += 1
        defer { isBusy = false }
        do { session = try await service.startSession(sessionId: session.id); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func end() async {
        guard !isBusy else { return }
        isBusy = true; revision += 1
        defer { isBusy = false }
        do { session = try await service.endSession(sessionId: session.id, moodAfter: nil); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func cancel() async {
        guard !isBusy else { return }
        isBusy = true; revision += 1
        defer { isBusy = false }
        do { session = try await service.cancelSession(sessionId: session.id); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

struct PeerFindMentorView: View {
    let service: PeerSupportService

    var body: some View {
        Text("Find a mentor who understands your journey")
            .navigationTitle("Find Mentor")
    }
}

struct MentorshipDetailView: View {
    let mentorship: DBMentorship
    let service: PeerSupportService

    var body: some View {
        Text("Mentorship details")
            .navigationTitle("Mentorship")
    }
}

struct ListenerDashboardView: View {
    let listener: DBListener
    let service: PeerSupportService

    var body: some View {
        Text("Listener dashboard")
            .navigationTitle("Listener Dashboard")
    }
}

struct BecomeListenerView: View {
    let service: PeerSupportService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Becoming a peer listener is a meaningful way to give back while reinforcing your own wellness journey.")
                        .multilineTextAlignment(.center)

                    // Requirements section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Requirements")
                            .font(.headline)

                        RequirementRow(icon: "calendar", text: "30+ days on the platform")
                        RequirementRow(icon: "figure.mind.and.body", text: "Completed 10+ exercises")
                        RequirementRow(icon: "book.fill", text: "Complete 4 training modules")
                        RequirementRow(icon: "checkmark.circle", text: "Pass certification quiz (80%+)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Become a Listener")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct RequirementRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ShareWisdomSheet: View {
    let service: PeerSupportService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var selectedCategory: DBCommunityWisdom.WisdomCategory = .coping
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(DBCommunityWisdom.WisdomCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }

                Section("Your Wisdom") {
                    TextField("Title", text: $title)
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }

                Section {
                    Text("Your submission will be reviewed before being published to the community.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Share Wisdom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        submitWisdom()
                    }
                    .disabled(title.isEmpty || content.isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submitWisdom() {
        isSubmitting = true
        Task {
            do {
                try await service.submitWisdom(
                    title: title,
                    content: content,
                    category: selectedCategory,
                    tags: nil
                )
                dismiss()
            } catch {
                Log.social.error("Failed to submit wisdom", error: error)
            }
            isSubmitting = false
        }
    }
}

struct GratitudeWallView: View {
    let service: PeerSupportService
    @State private var gratitudeItems: [DBGratitudeAction] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if gratitudeItems.isEmpty {
                ContentUnavailableView(
                    "No Gratitude Yet",
                    systemImage: "heart",
                    description: Text("Be the first to share some gratitude!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(gratitudeItems) { item in
                            GratitudeItemCard(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Gratitude Wall")
        .task {
            do {
                gratitudeItems = try await service.fetchPublicGratitude()
            } catch {
                Log.social.error("Failed to fetch gratitude", error: error)
            }
            isLoading = false
        }
    }
}

struct GratitudeItemCard: View {
    let item: DBGratitudeAction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.actionType.icon)
                .font(.title2)
                .foregroundStyle(colorForType(item.actionType))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.actionType.displayName)
                    .font(.subheadline.bold())
                if let message = item.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func colorForType(_ type: DBGratitudeAction.ActionType) -> Color {
        switch type {
        case .thankListener: return .red
        case .communityHug: return .pink
        case .wisdomShare: return .yellow
        case .storySpotlight: return .orange
        case .donation: return .green
        }
    }
}

struct CommunityWisdomView: View {
    let service: PeerSupportService
    @State private var wisdom: [DBCommunityWisdom] = []
    @State private var selectedCategory: DBCommunityWisdom.WisdomCategory?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PeerSupportCategoryChip(
                        title: "All",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                        Task { await loadWisdom() }
                    }

                    ForEach(DBCommunityWisdom.WisdomCategory.allCases, id: \.self) { category in
                        PeerSupportCategoryChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                            Task { await loadWisdom() }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if wisdom.isEmpty {
                ContentUnavailableView(
                    "No Wisdom Yet",
                    systemImage: "lightbulb",
                    description: Text("Be the first to share some wisdom!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(wisdom) { item in
                            WisdomDetailCard(wisdom: item, service: service)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Community Wisdom")
        .task {
            await loadWisdom()
        }
    }

    private func loadWisdom() async {
        isLoading = true
        do {
            wisdom = try await service.fetchCommunityWisdom(category: selectedCategory)
        } catch {
            Log.social.error("Failed to fetch wisdom", error: error)
        }
        isLoading = false
    }
}

private struct PeerSupportCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct WisdomDetailCard: View {
    let wisdom: DBCommunityWisdom
    let service: PeerSupportService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: wisdom.category.icon)
                    .foregroundStyle(.yellow)
                Text(wisdom.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        Task {
                            try? await service.markWisdomAsHelpful(wisdomId: wisdom.id)
                        }
                    } label: {
                        Label("\(wisdom.helpfulCount)", systemImage: "hand.thumbsup")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(wisdom.title)
                .font(.headline)

            Text(wisdom.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let tags = wisdom.tags, !tags.isEmpty {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PeerSupportHubView(supabase: DependencyContainer.preview.supabase)
        .environmentObject(DependencyContainer.preview)
}
