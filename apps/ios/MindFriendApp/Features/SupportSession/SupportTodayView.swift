import SwiftUI

struct SupportTodayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var pins: SupportPinStore
    @State private var isWorking = false
    @State private var error: String?
    @State private var closeCandidate: SupportSession?
    @State private var simplerView = false
    @State private var isEditingPins = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var resumable: SupportSession? { coordinator.unfinishedSessions.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(SupportGreeting.text(displayName: appState.currentUser?.displayName))
                            .font(.largeTitle.weight(.semibold)).foregroundStyle(SupportTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("A little room for what matters to you.")
                            .font(.body).foregroundStyle(SupportTheme.textSecondary)
                    }
                    focusCard
                    if simplerView {
                        Button("Turn off simpler view") {
                            SupportSimplerViewPreference.setEnabled(false, ownerID: coordinator.identity.ownerID)
                            simplerView = false
                        }.frame(minHeight: SupportTheme.minimumTarget)
                    } else {
                        quickWaysIn
                        progressCard
                        if !pins.pins.isEmpty { pinnedSection }
                    }
                    NavigationLink("View your history") { SupportSessionListView() }.frame(minHeight: SupportTheme.minimumTarget)
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline) }
                    if let message = coordinator.localSaveError {
                        Label(message, systemImage: "exclamationmark.circle").font(.subheadline)
                    }
                }
                .frame(maxWidth: SupportTheme.readableWidth, alignment: .leading)
                .padding(SupportTheme.Spacing.m).frame(maxWidth: .infinity)
            }
            .supportScreen()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { appState.showCrisisResources = true } label: { Image(systemName: "lifepreserver") }
                        .accessibilityLabel("Support and crisis resources")
                }
            }
            .alert("Close this session?", isPresented: Binding(
                get: { closeCandidate != nil }, set: { if !$0 { closeCandidate = nil } }), presenting: closeCandidate) { candidate in
                Button("Save and leave", role: .cancel) { self.closeCandidate = nil }
                Button("End unfinished work and close", role: .destructive) {
                    run {
                        try await coordinator.close(candidate.id); self.closeCandidate = nil
                        appState.celebrateCompletion(String(localized: "Session closed"), soft: true)
                    }
                }
            } message: { _ in Text("Unfinished activities and saved steps will be stopped or dismissed. They will not be marked completed.") }
        }
        .tint(SupportTheme.accent)
        .onAppear { simplerView = SupportSimplerViewPreference.isEnabled(ownerID: coordinator.identity.ownerID) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            simplerView = SupportSimplerViewPreference.isEnabled(ownerID: coordinator.identity.ownerID)
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            if let session = resumable {
                Text(Date().timeIntervalSince(session.updatedAt) > 14 * 86_400 ? "Previous session available" : "Continue where you left off")
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(resumeLabel(session)).foregroundStyle(SupportTheme.textSecondary)
                Button("Continue") { resume(session) }.buttonStyle(.supportPrimary)
                Button("Start something else") { startConversation() }.frame(minHeight: SupportTheme.minimumTarget)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SupportTheme.Spacing.m) { sessionActions(session) }
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) { sessionActions(session) }
                }
                .font(.subheadline)
                if coordinator.unfinishedSessions.count > 1 {
                    NavigationLink("Other unfinished sessions (\(coordinator.unfinishedSessions.count - 1))") {
                        SupportSessionListView(unfinishedOnly: true)
                    }.frame(minHeight: SupportTheme.minimumTarget)
                }
            } else {
                Text("What would help right now?").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("We can talk it through or try one small thing.").foregroundStyle(SupportTheme.textSecondary)
                Button("Start a conversation") { startConversation() }.buttonStyle(.supportPrimary)
            }
        }
        .disabled(isWorking)
        .frame(maxWidth: .infinity, alignment: .leading)
        .supportCard()
    }

    private func sessionActions(_ session: SupportSession) -> some View {
        Group {
            NavigationLink("View session") { SupportSessionDetailView(sessionID: session.id) }
                .frame(minHeight: SupportTheme.minimumTarget)
            Button("Close session") { closeCandidate = session }
                .frame(minHeight: SupportTheme.minimumTarget)
        }
    }

    private var quickWaysIn: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Quick ways in").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: SupportTheme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: SupportTheme.Spacing.xs))
            layout {
                NavigationLink { MoodCheckInView().environment(\.supportRootEmbedded, true) } label: {
                    quickLabel("Check in", icon: "face.smiling")
                }
                .accessibilityLabel("Check in with yourself")
                NavigationLink { SupportDestinationView(destination: .quickBreathing) } label: {
                    quickLabel("1-minute breathing", icon: "wind")
                }
                SupportActivityChoiceButton(template: .untangleThoughtV1, origin: .today,
                    title: "Untangle a thought", icon: "text.bubble")
            }
            .buttonStyle(.supportSecondary)
            .fixedSize(horizontal: false, vertical: true)
            // These existing session entries stay available without competing with conversation.
            SupportActivityChoiceButton(template: .groundPresentV1, origin: .today, title: "Settle for a moment")
                .frame(minHeight: SupportTheme.minimumTarget)
            SupportActivityChoiceButton(template: .chooseStepV1, origin: .today, title: "Choose a next step")
                .frame(minHeight: SupportTheme.minimumTarget)
        }
    }

    private func quickLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            // Symbol weight matches the medium-weight label beside it.
            Image(systemName: icon).font(.title2.weight(.medium)).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        // Equal-height tiles: each fills the row, which takes the tallest tile's height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("A little progress").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            // The cached quest can be yesterday's when the app stays open overnight; only today's is shown.
            if let quest = appState.todayQuest, quest.localDate == DateFormatter.dateOnly.string(from: Date()) {
                NavigationLink { QuestDetailView(quest: quest) } label: {
                    SupportRowLabel(title: quest.template.title,
                        subtitle: quest.status == .completed ? "Today's quest is complete" : "Today's quest",
                        icon: quest.status == .completed ? "checkmark.circle" : "leaf")
                }
            } else {
                NavigationLink { SupportDestinationView(destination: .dailyQuest) } label: {
                    SupportRowLabel(title: "Today's quest", subtitle: "Choose something that fits your day", icon: "leaf")
                }
            }
            if let stats = appState.currentUser?.stats {
                let level = UserLevel.from(stats: stats)
                Divider().overlay(SupportTheme.separator)
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Level \(stats.level) · \(stats.levelTitle)").font(.headline)
                    Text("\(stats.xpTotal) XP total").font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                    ProgressView(value: min(1, max(0, level.progress)))
                        .tint(SupportTheme.accent)
                        .accessibilityLabel("Progress to next level")
                    Text(level.level < 50 ? "\(level.xpToNextLevel) XP to the next level" : "Highest level reached")
                        .font(.caption).foregroundStyle(SupportTheme.textSecondary)
                }
            } else {
                Text("Your XP and level will appear here after your account updates.")
                    .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(SupportTheme.textPrimary)
        .supportCard()
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Pinned to Today").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    editPinsButton
                }
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Pinned to Today").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    editPinsButton
                }
            }
            ForEach(pins.pins) { pin in
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    NavigationLink { SupportPinnedDestinationView(pin: pin) } label: {
                        SupportRowLabel(title: pin.title, subtitle: pin.destination.subtitle, icon: pin.destination.icon)
                    }
                    .buttonStyle(.plain)
                    if isEditingPins {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: SupportTheme.Spacing.xs) { pinControls(pin) }
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) { pinControls(pin) }
                        }
                    }
                }
                .supportCard()
            }
        }
    }

    private var editPinsButton: some View {
        Button(isEditingPins ? "Done" : "Edit") { isEditingPins.toggle() }
            .frame(minHeight: SupportTheme.minimumTarget)
            .accessibilityLabel(isEditingPins ? "Finish editing pinned shortcuts" : "Edit pinned shortcuts")
    }

    private func pinControls(_ pin: SupportPin) -> some View {
        Group {
            Button { pins.moveUp(pin) } label: { Image(systemName: "arrow.up") }
                .accessibilityLabel("Move up \(pin.title)")
                .disabled(pins.pins.first?.id == pin.id)
            Button { pins.moveDown(pin) } label: { Image(systemName: "arrow.down") }
                .accessibilityLabel("Move down \(pin.title)")
                .disabled(pins.pins.last?.id == pin.id)
            Button("Unpin") { pins.unpin(pin) }.accessibilityLabel("Unpin \(pin.title)")
        }
        .buttonStyle(.supportSecondary)
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

/// "Good evening, Synthetic": the time of day and the first word of the account's name. It never
/// infers how the person feels (spec 5.1), and leaves out placeholders, handles and email prefixes.
enum SupportGreeting {
    static func text(displayName: String?, at date: Date = Date(), calendar: Calendar = .current) -> String {
        let greeting = TimeOfDay.at(hour: calendar.component(.hour, from: date)).greeting
        guard let name = firstName(from: displayName) else { return greeting }
        return "\(greeting), \(name)"
    }

    static func firstName(from displayName: String?) -> String? {
        guard let first = displayName?.split(whereSeparator: \.isWhitespace).first.map(String.init),
              first != "MindFriend", first.first?.isLowercase == false,
              !first.contains(where: { $0 == "@" || $0 == "_" || $0 == "." || $0.isNumber }) else { return nil }
        return first
    }
}

struct SupportSessionListView: View {
    var unfinishedOnly = false
    var body: some View { SupportHistoryView(unfinishedOnly: unfinishedOnly) }
}

struct SupportSavedStepsView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        List {
            ForEach(coordinator.savedSteps) { activity in
                Section {
                    NavigationLink { SupportSavedStepDetailView(activityID: activity.id) } label: { Text(activity.step?.actionText ?? "") }
                    Text("Saved on this device" + (activity.syncStatus == .synced ? " and to your account" : " · account sync pending"))
                        .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                    Button("I did it") { choose(.didIt, activity: activity) }
                    Button("Not now") { choose(.notNow, activity: activity) }
                    NavigationLink("View session") { SupportSessionDetailView(sessionID: activity.sessionID) }
                }
                .listRowBackground(SupportTheme.surface)
            }
            if let error { Text(error) }
        }
        .disabled(isSaving)
        .navigationTitle("Saved steps")
        .supportScreen()
        .overlay {
            if coordinator.savedSteps.isEmpty { ContentUnavailableView("No saved steps", systemImage: "checkmark.circle",
                description: Text("Save a next step during a session to return to it here.")) }
        }
    }

    private func choose(_ choice: SupportStepChoice, activity: SupportActivity) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await coordinator.chooseStep(activity.id, choice: choice, text: activity.step?.actionText)
                if choice == .didIt { appState.celebrateCompletion(String(localized: "Step done")) }
            } catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }
}

struct SupportSessionDetailView: View {
    let sessionID: UUID
    var body: some View { SupportHistoryDetailView(sessionID: sessionID) }
}

struct SupportSavedStepDetailView: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
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
                .listRowBackground(SupportTheme.surface)
                Section {
                    if let at = step.reminderAt {
                        if step.reminderState == .scheduled {
                            Text(at > Date() ? "Reminder set" : "Reminder time passed")
                            Text(at, style: .date) + Text(" · ") + Text(at, style: .time)
                            Text(step.reminderTimeZoneIdentifier ?? zone).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                        } else {
                            Text(step.reminderState == .pending ? "Reminder not yet confirmed" : "Reminder was not set. Try again.")
                        }
                    }
                    DatePicker("Remind me", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                    Text("Time zone: \(zone)").font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
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
                .listRowBackground(SupportTheme.surface)
                NavigationLink("View session") { SupportSessionDetailView(sessionID: activity.sessionID) }
            } else {
                Text("This step is no longer waiting. Its session remains in History.")
            }
            if let error { Section { Text(error).foregroundStyle(SupportTheme.textPrimary) } }
        }
        .disabled(isWorking)
        .navigationTitle("Saved step")
        .supportScreen()
        .task(id: activityID) {
            if let step = activity?.step, let at = step.reminderAt, at > Date() {
                date = at; zone = step.reminderTimeZoneIdentifier ?? zone
            }
        }
    }

    private func choose(_ choice: SupportStepChoice, activity: SupportActivity) {
        run {
            try await coordinator.chooseStep(activity.id, choice: choice, text: activity.step?.actionText)
            if choice == .didIt { appState.celebrateCompletion(String(localized: "Step done")) }
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
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(activity.step?.actionText ?? "Saved step")
                            Text(activity.step?.reminderState == .scheduled ? "On this device" : "Not set · needs attention")
                                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
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
            .listRowBackground(SupportTheme.surface)
            if let error { Text(error) }
        }
        .disabled(isWorking)
        .overlay { if reminders.isEmpty { ContentUnavailableView("No step reminders", systemImage: "bell.slash") } }
        .navigationTitle("Step reminders")
        .supportScreen()
    }
}
