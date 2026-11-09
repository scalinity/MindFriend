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
                Button("Continue") { resume(session) }.buttonStyle(.borderedProminent).foregroundStyle(SupportTheme.onAccent).frame(minHeight: 48)
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
                Button("Start a conversation") { startConversation() }.buttonStyle(.borderedProminent).foregroundStyle(SupportTheme.onAccent).frame(minHeight: 48)
                ForEach(SupportActivityTemplateKey.allCases, id: \.self) { template in
                    SupportActivityChoiceButton(template: template, origin: .today, title: template.intention)
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
    var unfinishedOnly = false
    var body: some View { SupportHistoryView(unfinishedOnly: unfinishedOnly) }
}

struct SupportSavedStepsView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        List {
            ForEach(coordinator.savedSteps) { activity in
                Section {
                    NavigationLink { SupportSavedStepDetailView(activityID: activity.id) } label: { Text(activity.step?.actionText ?? "") }
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
    let sessionID: UUID
    var body: some View { SupportHistoryDetailView(sessionID: sessionID) }
}

struct SupportSavedStepDetailView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @Environment(\.dismiss) private var dismiss
    let activityID: UUID
    @State private var date = Date().addingTimeInterval(3_600)
    @State private var zone = TimeZone.current.identifier
    @State private var isWorking = false
    @State private var error: String?
    private var activity: SupportActivity? { coordinator.journal.activities[activityID] }

    var body: some View {
        Form {
            if let activity, let step = activity.step, step.state == .saved {
                Section("Your next step") {
                    Text(step.actionText)
                    Button("I did it") { choose(.didIt, activity: activity) }
                    Button("Not now") { choose(.notNow, activity: activity) }
                }
                Section {
                    if let at = step.reminderAt {
                        if step.reminderState == .scheduled {
                            Text(at > Date() ? "Reminder set" : "Reminder time passed")
                            Text(at, style: .date) + Text(" · ") + Text(at, style: .time)
                            Text(step.reminderTimeZoneIdentifier ?? zone).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text(step.reminderState == .pending ? "Reminder not yet confirmed" : "Reminder was not set. Try again.")
                        }
                    }
                    DatePicker("Remind me", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                    Text("Time zone: \(zone)").font(.subheadline).foregroundStyle(.secondary)
                    Button("Set reminder") {
                        run { try await coordinator.setReminder(activityID, at: date, timeZoneIdentifier: zone) }
                    }
                    if step.reminderAt != nil {
                        Button("Cancel reminder", role: .destructive) { run { try await coordinator.cancelReminder(activityID) } }
                    }
                    if step.reminderState == .failed {
                        Button("Notification settings") { NotificationPermissionManager().openSettings() }
                    }
                } header: { Text("Reminder · on this device") }
                  footer: { Text("One reminder, with the message “A step you saved is here when you want it.” Its time stays fixed if you travel. Other devices do not schedule it.") }
                NavigationLink("View session") { SupportSessionDetailView(sessionID: activity.sessionID) }
            } else {
                Text("This step is no longer waiting. Its session remains in History.")
            }
            if let error { Section { Text(error).foregroundStyle(.primary) } }
        }
        .disabled(isWorking)
        .navigationTitle("Saved step")
        .supportCanvas()
        .task(id: activityID) {
            if let step = activity?.step, let at = step.reminderAt, at > Date() {
                date = at; zone = step.reminderTimeZoneIdentifier ?? zone
            }
        }
    }

    private func choose(_ choice: SupportStepChoice, activity: SupportActivity) {
        run {
            try await coordinator.chooseStep(activity.id, choice: choice, text: activity.step?.actionText)
            dismiss()
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

struct SupportStepReminderSettingsView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @State private var error: String?
    @State private var isWorking = false
    private var reminders: [SupportActivity] { coordinator.savedSteps.filter { $0.step?.reminderAt != nil } }
    var body: some View {
        List {
            Section {
                ForEach(reminders) { activity in
                    NavigationLink { SupportSavedStepDetailView(activityID: activity.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.step?.actionText ?? "Saved step")
                            Text(activity.step?.reminderState == .scheduled ? "On this device" : "Not set · needs attention")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if !reminders.isEmpty {
                    Button("Cancel all step reminders on this device", role: .destructive) {
                        let ids = reminders.map(\.id)
                        isWorking = true
                        Task { @MainActor in
                            defer { isWorking = false }
                            do { for id in ids { try await coordinator.cancelReminder(id) } }
                            catch { self.error = SupportSessionCoordinator.message(for: error) }
                        }
                    }
                }
            } footer: { Text("Steps stay saved when their reminders are cancelled.") }
            if let error { Text(error) }
        }
        .disabled(isWorking)
        .overlay { if reminders.isEmpty { ContentUnavailableView("No step reminders", systemImage: "bell.slash") } }
        .navigationTitle("Step reminders")
        .supportCanvas()
    }
}
