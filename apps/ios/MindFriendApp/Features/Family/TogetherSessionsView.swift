import SwiftUI
import AVFoundation

/// View for together sessions (synchronized family activities)
struct TogetherSessionsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var sessions: [TogetherSession] = []
    @State private var templates: [TogetherTemplate] = []
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var selectedSession: TogetherSession?
    @State private var errorMessage: String?
    let familyGroup: FamilyWellnessGroup

    var activeSessions: [TogetherSession] {
        sessions.filter { $0.status == .inProgress }
    }

    var upcomingSessions: [TogetherSession] {
        sessions.filter { $0.status == .pending }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Active Sessions
                    if !activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Currently Active")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(activeSessions, id: \.id) { session in
                                TogetherActiveSessionCard(session: session) { selectedSession = session }
                            }
                        }
                    }

                    // Upcoming Sessions
                    if !upcomingSessions.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Upcoming")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(upcomingSessions, id: \.id) { session in
                                Button { selectedSession = session } label: { SessionCard(session: session) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    // Start New Activity
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Start an Activity")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(templates.prefix(4), id: \.id) { template in
                            TogetherTemplateCard(template: template) {
                                Task { await start(template) }
                            }
                            .disabled(isStarting)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).padding(.horizontal)
                    }
                    if sessions.isEmpty && templates.isEmpty && !isLoading {
                        VStack(spacing: SupportTheme.Spacing.m) {
                            Image(systemName: "person.2.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(SupportTheme.textSecondary)
                            Text("No activities yet")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.xl)
                    }
                }
                .padding(.vertical)
            }

            if isLoading || isStarting {
                ProgressView()
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Together Sessions")
        .task { await loadData() }
        .refreshable { await loadData() }
        .sheet(item: $selectedSession, onDismiss: { Task { await loadData() } }) { session in
            NavigationStack {
                TogetherSessionDetailView(
                    session: session,
                    template: templates.first { $0.id == session.togetherTemplateId },
                    service: container.familyService,
                    userId: container.supabaseAuthService.userId
                )
            }
        }
    }

    private func start(_ template: TogetherTemplate) async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            selectedSession = try await container.familyService.startTogetherSession(templateId: template.id, title: template.title)
            sessions = container.familyService.togetherSessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let sessionsTask = container.familyService.fetchTogetherSessions()
            async let templatesTask = container.familyService.fetchTogetherTemplates()

            sessions = try await sessionsTask
            templates = try await templatesTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            Log.family.error("Failed to load data", error: error)
        }
    }
}

private struct TogetherSessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: FamilyService
    @State private var session: TogetherSession
    let template: TogetherTemplate?
    let userId: UUID?
    @State private var participants: [TogetherParticipant] = []
    @State private var members: [FamilyWellnessMember] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var revision = 0
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false

    init(session: TogetherSession, template: TogetherTemplate?, service: FamilyService, userId: UUID?) {
        _session = State(initialValue: session)
        self.template = template
        self.service = service
        self.userId = userId
    }

    private var myParticipant: TogetherParticipant? {
        guard let userId, let member = members.first(where: { UUID(uuidString: $0.userId) == userId }) else { return nil }
        return participants.first { $0.memberId == member.id }
    }
    private var isCreator: Bool { userId != nil && UUID(uuidString: session.createdBy) == userId }
    private var isOpen: Bool { session.status == .pending || session.status == .inProgress }

    var body: some View {
        List {
            Section {
                Text(session.title).font(.headline)
                Text(session.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .foregroundStyle(SupportTheme.textSecondary)
                if let template {
                    if let description = template.description { Text(description) }
                    Label(template.formattedDuration, systemImage: "clock")
                }
                if session.status == .pending {
                    Text("Waiting for at least \(session.minimumParticipants) participants to join.")
                        .font(.caption).foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .listRowBackground(SupportTheme.surface)
            Section("Participants") {
                ForEach(participants) { participant in
                    HStack {
                        Text(members.first { $0.id == participant.memberId }?.displayName ?? "Family member")
                        Spacer()
                        Text(participant.status.displayName).foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .listRowBackground(SupportTheme.surface)
            if let audioPlayer {
                Section("Guidance") {
                    Button(isPlaying ? "Pause guidance" : "Play guidance", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                        if isPlaying { audioPlayer.pause() } else { audioPlayer.play() }
                        isPlaying.toggle()
                    }
                    .disabled(session.status != .inProgress || myParticipant?.status != .joined)
                }
                .listRowBackground(SupportTheme.surface)
            }
            if isOpen {
                Section {
                    if myParticipant?.status == .invited {
                        Button("Join Activity") { Task { await perform { try await service.joinTogetherSession(sessionId: session.id) } } }
                    }
                    if isCreator && session.status == .pending {
                        Button("Begin Activity") { Task { await perform { try await service.beginTogetherSession(sessionId: session.id) } } }
                            .disabled(participants.filter { $0.status == .joined }.count < session.minimumParticipants)
                    }
                    if isCreator && session.status == .inProgress {
                        Button("Finish Activity") { Task { await perform { try await service.completeTogetherSession(sessionId: session.id) } } }
                    }
                    if isBusy { ProgressView() }
                }
                .listRowBackground(SupportTheme.surface)
                .disabled(isBusy)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Refresh") { Task { await refresh() } }
                }
                .listRowBackground(SupportTheme.surface)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Family Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            if let urlString = template?.audioUrl, let url = URL(string: urlString) { audioPlayer = AVPlayer(url: url) }
            while !Task.isCancelled {
                if !isBusy { await refresh() }
                if !isOpen { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .refreshable { await refresh() }
        .onDisappear { audioPlayer?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === audioPlayer?.currentItem else { return }
            isPlaying = false
            audioPlayer?.seek(to: .zero)
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === audioPlayer?.currentItem else { return }
            isPlaying = false
            errorMessage = "Guided audio could not play. Try again when your connection is available."
        }
    }

    private func refresh() async {
        let startedRevision = revision
        do {
            async let savedSession = service.fetchTogetherSession(sessionId: session.id)
            async let savedParticipants = service.fetchSessionParticipants(sessionId: session.id)
            async let savedMembers = service.fetchFamilyMembers()
            let refreshed = try await (savedSession, savedParticipants, savedMembers)
            try Task.checkCancellation()
            guard revision == startedRevision else { return }
            session = refreshed.0
            participants = refreshed.1
            members = refreshed.2
            if !isOpen { audioPlayer?.pause(); isPlaying = false }
            errorMessage = nil
        } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        revision += 1
        defer { isBusy = false }
        do { try await action(); await refresh() } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Supporting Cards

struct TogetherActiveSessionCard: View {
    let session: TogetherSession
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(session.title)
                        .font(.headline)
                    Text("In Progress")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SupportTheme.accent)
            }

            if let timeRemaining = session.timeRemaining {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("Time remaining: \(formatTimeInterval(timeRemaining))")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Button(action: action) {
                Text("View Details")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportSecondary)
        }
        .supportCard()
        .padding(.horizontal)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SessionCard: View {
    let session: TogetherSession

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let scheduledFor = session.scheduledFor {
                    Text(scheduledFor.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
        .padding(.horizontal)
    }
}

struct TogetherTemplateCard: View {
    let template: TogetherTemplate
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(template.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text(template.formattedDuration)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            Button(action: action) {
                Text("Start Activity")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
            }
            .buttonStyle(.supportSecondary)
        }
        .supportCard()
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        TogetherSessionsView(
            familyGroup: .init(
                id: "test",
                name: "Test Family",
                adminUserId: "admin",
                circleId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        .environmentObject(DependencyContainer.preview)
    }
}
