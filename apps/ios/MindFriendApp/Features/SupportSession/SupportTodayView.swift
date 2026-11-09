import SwiftUI

struct SupportTodayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var pins: SupportPinStore
    @State private var isWorking = false
    @State private var error: String?
    @State private var closeCandidate: SupportSession?
    @State private var simplerView = false

    private var resumable: SupportSession? { coordinator.unfinishedSessions.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A little room for what matters to you.")
                        .font(.body).foregroundStyle(SupportTheme.textSecondary)
                    focusCard
                    if simplerView {
                        Button("Turn off simpler view") {
                            SupportSimplerViewPreference.setEnabled(false, ownerID: coordinator.identity.ownerID)
                            simplerView = false
                        }.frame(minHeight: 44)
                    } else {
                        NavigationLink { MoodCheckInView() } label: {
                            SupportRowLabel(title: "Check in with yourself", subtitle: "Optional", icon: "face.smiling")
                        }.buttonStyle(.plain)
                    }
                    if !simplerView && !pins.pins.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pinned to Today").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            ForEach(pins.pins) { destination in
                                HStack(alignment: .top) {
                                    NavigationLink { SupportPinnedDestinationView(pin: destination) } label: {
                                        SupportRowLabel(title: destination.title, subtitle: destination.destination.subtitle, icon: destination.destination.icon)
                                    }
                                    Spacer(minLength: 8)
                                    Menu {
                                        Button("Move up") { pins.moveUp(destination) }
                                        Button("Move down") { pins.moveDown(destination) }
                                        Button("Unpin") { pins.unpin(destination) }
                                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Options for \(destination.title)")
                                }
                            }
                        }
                    }
                    NavigationLink("View your history") { SupportSessionListView() }.frame(minHeight: 44)
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline) }
                    if let message = coordinator.localSaveError {
                        Label(message, systemImage: "exclamationmark.circle").font(.subheadline)
                    }
                }
                .frame(maxWidth: SupportTheme.readableWidth, alignment: .leading)
                .padding(16).frame(maxWidth: .infinity)
            }
            .background(SupportTheme.canvas)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { appState.showCrisisResources = true } label: { Image(systemName: "lifepreserver") }
                        .accessibilityLabel("Support and crisis resources")
                }
            }
            .confirmationDialog("Close this session?", isPresented: Binding(
                get: { closeCandidate != nil }, set: { if !$0 { closeCandidate = nil } }), titleVisibility: .visible) {
                if let closeCandidate {
                    Button("Save and leave", role: .cancel) { self.closeCandidate = nil }
                    Button("End unfinished work and close", role: .destructive) {
                        run { try await coordinator.close(closeCandidate.id); self.closeCandidate = nil }
                    }
                }
            } message: { Text("Unfinished activities and saved steps will be stopped or dismissed. They will not be marked completed.") }
        }
        .tint(SupportTheme.accent)
        .onAppear { simplerView = SupportSimplerViewPreference.isEnabled(ownerID: coordinator.identity.ownerID) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            simplerView = SupportSimplerViewPreference.isEnabled(ownerID: coordinator.identity.ownerID)
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let session = resumable {
                Text(Date().timeIntervalSince(session.updatedAt) > 14 * 86_400 ? "Previous session available" : "Continue where you left off")
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(resumeLabel(session)).foregroundStyle(SupportTheme.textSecondary)
                Button("Continue") { resume(session) }.buttonStyle(.borderedProminent).frame(minHeight: 48)
                Button("Start something else") { startConversation() }.frame(minHeight: 44)
                HStack {
                    NavigationLink("View session") { SupportSessionDetailView(sessionID: session.id) }
                    Spacer()
                    Button("Close session") { closeCandidate = session }
                }.font(.subheadline).frame(minHeight: 44)
                if coordinator.unfinishedSessions.count > 1 {
                    NavigationLink("Other unfinished sessions (\(coordinator.unfinishedSessions.count - 1))") {
                        SupportSessionListView(unfinishedOnly: true)
                    }.frame(minHeight: 44)
                }
            } else {
                Text("What would help right now?").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("We can talk it through or try one small thing.").foregroundStyle(SupportTheme.textSecondary)
                Button("Start a conversation") { startConversation() }.buttonStyle(.borderedProminent).frame(minHeight: 48)
                ForEach(SupportActivityTemplateKey.allCases, id: \.self) { template in
                    Button(template.intention) { run { _ = try await coordinator.start(template, origin: .today) } }
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .disabled(isWorking)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func resumeLabel(_ session: SupportSession) -> String {
        if let aid = session.selectedActivityID, let activity = coordinator.journal.activities[aid], activity.status.isUnfinished {
            if activity.step?.state == .saved { return "A next step is saved" }
            let count = activity.checkpoint.completedStepIDs.count + activity.checkpoint.skippedStepIDs.count
            return "\(activity.templateKey.title) · step \(min(count + 1, activity.templateKey.prompts.count)) of \(activity.templateKey.prompts.count)"
        }
        return (coordinator.journal.drafts[session.id] ?? "").isEmpty ? "Conversation available" : "Conversation draft saved"
    }

    private func startConversation() {
        run {
            _ = try await coordinator.createSession()
            appState.selectedTab = .chat
            appState.shouldOpenNewChat = true
        }
    }

    private func resume(_ session: SupportSession) {
        run {
            try coordinator.selectSession(session.id)
            if let id = session.selectedActivityID, coordinator.journal.activities[id]?.status.isUnfinished == true {
                try await coordinator.resume(id, origin: .today)
            } else {
                appState.selectedTab = .chat
                if let conversation = session.conversationID {
                    DeepLinkRouter.shared.handleRoute(.chat(conversationId: conversation.uuidString), appState: appState)
                } else { appState.shouldOpenNewChat = true }
            }
        }
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true; error = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { try await body() } catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }
}

struct SupportSessionListView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    var unfinishedOnly = false
    @State private var error: String?
    private var sessions: [SupportSession] {
        if unfinishedOnly { return coordinator.unfinishedSessions }
        return coordinator.journal.sessions.values.filter { $0.status != .deleted }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        List {
            ForEach(coordinator.journal.failures.filter { $0.kind == .deleteSession }, id: \.operationID) { failure in
                Section("Session removal needs attention") {
                    Text("The session was removed from this device. Its account copy has not been confirmed removed.")
                    Button("Try removing the account copy again") {
                        Task {
                            do { try await coordinator.retryDeletion(failure.sessionID) }
                            catch { self.error = SupportSessionCoordinator.message(for: error) }
                        }
                    }
                }
            }
            Section {
                ForEach(sessions) { session in
                    NavigationLink { SupportSessionDetailView(sessionID: session.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                            Text(session.status == .closed ? "Closed" : "Open").font(.subheadline).foregroundStyle(.secondary)
                            Text(session.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: { Text("Sessions saved on this device. Existing conversations and other records remain available in You.") }
            if let error { Text(error) }
        }
        .navigationTitle(unfinishedOnly ? "Unfinished sessions" : "Saved sessions")
        .overlay { if sessions.isEmpty { ContentUnavailableView("No saved sessions", systemImage: "text.book.closed") } }
        .supportCanvas()
    }
}

struct SupportSavedStepsView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        List {
            ForEach(coordinator.savedSteps) { activity in
                Section {
                    Text(activity.step?.actionText ?? "")
                    Text("Saved on this device" + (activity.syncStatus == .synced ? " and to your account" : " · account sync pending"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("I did it") { choose(.didIt, activity: activity) }
                    Button("Not now") { choose(.notNow, activity: activity) }
                    NavigationLink("View session") { SupportSessionDetailView(sessionID: activity.sessionID) }
                }
            }
            if let error { Text(error) }
        }
        .disabled(isSaving)
        .navigationTitle("Saved steps")
        .supportCanvas()
        .overlay {
            if coordinator.savedSteps.isEmpty { ContentUnavailableView("No saved steps", systemImage: "checkmark.circle",
                description: Text("Save a next step during a session to return to it here.")) }
        }
    }

    private func choose(_ choice: SupportStepChoice, activity: SupportActivity) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do { try await coordinator.chooseStep(activity.id, choice: choice, text: activity.step?.actionText) }
            catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }
}

struct SupportSessionDetailView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    let sessionID: UUID
    @State private var error: String?
    var body: some View {
        List {
            if let session = coordinator.journal.sessions[sessionID] {
                Section {
                    Text(session.status == .closed ? "Closed session" : "Open session")
                    Text(session.syncStatus == .synced ? "Saved to your account" : "Saved on this device · account sync pending")
                }
                ForEach(coordinator.journal.activities(in: sessionID)) { activity in
                    Section(activity.templateKey.title) {
                        Text(activity.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        if let step = activity.step, step.state == .saved { Text(step.actionText) }
                        if activity.status.isUnfinished {
                            Button("Continue") {
                                Task { do { try await coordinator.resume(activity.id, origin: .today) }
                                    catch { self.error = SupportSessionCoordinator.message(for: error) } }
                            }
                        }
                    }
                }
                Section("Session history") {
                    ForEach(coordinator.journal.events(for: sessionID)) { event in
                        Text(event.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
            }
            if let error { Text(error) }
        }
        .navigationTitle(coordinator.journal.sessions[sessionID]?.title ?? "Session unavailable")
        .supportCanvas()
    }
}
