import SwiftUI

/// Rendering and editing state only. Acknowledged activity state lives in the coordinator's repository.
struct SupportActivityView: View {
    @ObservedObject var coordinator: SupportSessionCoordinator
    let presentation: SupportActivityPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @State private var discussion: SupportActivityDiscussionSnapshot?
    @AccessibilityFocusState private var headingFocused: Bool
    @FocusState private var fieldFocused: Bool
    @State private var askedForFirstPart = false
    @State private var answer = ""
    @State private var note = ""
    @State private var includeAnswers = false
    @State private var isSaving = false
    @State private var showPause = false
    @State private var showRecoveryChoice = false
    @State private var needsRecoveryChoice = false
    @State private var error: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var draftSavePending = false
    @State private var activeSince: Date?

    private var activity: SupportActivity? { coordinator.journal.activities[presentation.id] }
    private var promptIndex: Int {
        guard let activity else { return 0 }
        let acknowledged = Set(activity.checkpoint.completedStepIDs + activity.checkpoint.skippedStepIDs)
        return activity.templateKey.prompts.firstIndex { !acknowledged.contains($0.id) } ?? max(0, activity.templateKey.prompts.count - 1)
    }
    private var prompt: (id: String, text: String)? {
        guard let activity else { return nil }
        return activity.templateKey.prompts[promptIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let activity {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if activity.status.isTerminal { reflection(activity) }
                            else { work(activity) }
                            if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.primary) }
                            if needsRecoveryChoice {
                                Button("Review recovery files") { showRecoveryChoice = true }.frame(minHeight: 44)
                            }
                            Label(isSaving || draftSavePending ? "Saving on this device…" : "Saved on this device · account sync pending",
                                  systemImage: isSaving || draftSavePending ? "clock" : "checkmark.circle")
                                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: SupportTheme.readableWidth, alignment: .leading)
                        .padding(20).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(SupportTheme.canvas)
                    .safeAreaInset(edge: .bottom) {
                        // While typing, Next and Skip move into the keyboard toolbar.
                        if !fieldFocused && !activity.status.isTerminal && activity.kind != .chooseStep { progression(activity) }
                    }
                    .navigationTitle(activity.templateKey.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(activity.status.isTerminal ? "Done" : "Pause") {
                                if activity.status.isTerminal { leave() } else { showPause = true }
                            }
                            .disabled(isSaving)
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            if !activity.status.isTerminal && activity.kind != .chooseStep {
                                Button("Skip") { advance(skipped: true) }.disabled(isSaving)
                                Button(isLastPrompt(activity) ? "Finish" : "Next") { advance(skipped: false) }.disabled(isSaving)
                            }
                            Spacer()
                            Button("Done") { fieldFocused = false }
                        }
                    }
                } else {
                    ContentUnavailableView("Activity unavailable", systemImage: "doc.questionmark",
                                           description: Text("Your other saved work is still available."))
                }
            }
            .tint(SupportTheme.accent)
            .confirmationDialog("Pause this activity?", isPresented: $showPause, titleVisibility: .visible) {
                Button("Save and leave") { pause() }
                Button("Keep going", role: .cancel) {}
                Button("End this activity", role: .destructive) { finish(stopped: "user_ended") }
                if activity?.kind == .untangle {
                    Button("Discard this reflection", role: .destructive) {
                        perform {
                            try await coordinator.discardAnswers(presentation.id)
                            try await coordinator.doneForNow(presentation.sessionID)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text(activity?.kind == .untangle
                    ? "Ending records that you stopped. It never marks the activity completed. A Chat draft you prepared from these answers is separate and stays until you edit or delete it."
                    : "Ending records that you stopped. It never marks the activity completed.")
            }
            .alert("Discard earlier recovery files?", isPresented: $showRecoveryChoice) {
                Button("Keep recovery files", role: .cancel) {}
                Button("Discard recovery files", role: .destructive) {
                    perform { try await coordinator.discardRecoveryCopies() }
                }
            } message: {
                Text("These unreadable files can contain saved work from earlier sessions in this account. Removing them leaves the current readable journal intact and cannot be undone. Keep the files if there may be work you still need.")
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: $discussion) { snapshot in
            SupportActivityDiscussionView(snapshot: snapshot, coordinator: coordinator)
        }
        .task(id: presentation.id) { loadAnswer(); activeSince = Date() }
        .onChange(of: answer) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if activity?.status.isUnfinished == true { pause() }
            }
        }
        .onDisappear { draftTask?.cancel() }
    }

    @ViewBuilder private func work(_ activity: SupportActivity) -> some View {
        if activity.kind != .chooseStep {
            Text("Step \(promptIndex + 1) of \(activity.templateKey.prompts.count)")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
        }
        Text(askedForFirstPart && activity.kind == .chooseStep ? Self.firstPartPrompt : prompt?.text ?? "Choose a small step")
            .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            .accessibilityFocused($headingFocused)
        if activity.kind == .grounding {
            Text("You can participate silently or write something down. Skip any prompt. If a sense is unavailable, notice a different neutral detail.")
        } else if activity.kind == .untangle {
            Text(promptIndex == 2 ? "Keep your original wording if that feels right. Every prompt is optional." : "Write as much or as little as you want. You can skip this prompt.")
            Text("Saved to your account when synced. Shared with AI only when you choose.")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
        }
        if activity.kind == .untangle {
            Button("Ask for help") { showDiscussion() }.frame(minHeight: 44).disabled(isSaving)
        }
        TextField(activity.kind == .chooseStep ? "Your next step" : "Optional response", text: $answer, axis: .vertical)
            .lineLimit(3...10).supportField()
            .focused($fieldFocused)
            .disabled(isSaving)
            .accessibilityLabel(activity.kind == .chooseStep ? "Your next step" : "Optional response")
        if activity.kind == .chooseStep {
            Text("\(answer.unicodeScalars.count) of 400 characters").font(.caption)
            if !askedForFirstPart {
                Button("Make it smaller") { askForFirstPart() }.frame(minHeight: 44)
            }
            // The choices return when typing ends, so they never crowd the keyboard.
            if !fieldFocused {
                VStack(spacing: 12) {
                    Button("I did it") { choose(.didIt) }.buttonStyle(.borderedProminent).foregroundStyle(SupportTheme.onAccent)
                    Button("Save for later") { choose(.saveForLater) }.buttonStyle(.bordered)
                    Button("Not now") { choose(.notNow) }
                }
                .disabled(isSaving)
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
        }
    }

    /// Deterministic follow-up (spec 5.4): the same step, asked about its first part.
    static let firstPartPrompt = "What is the first part you could do?"

    private func askForFirstPart() {
        askedForFirstPart = true
        fieldFocused = true
        AccessibilityNotification.Announcement(Self.firstPartPrompt).post()
    }

    private func isLastPrompt(_ activity: SupportActivity) -> Bool {
        promptIndex == activity.templateKey.prompts.count - 1
    }

    private func progression(_ activity: SupportActivity) -> some View {
        VStack(spacing: 8) {
            Button(isLastPrompt(activity) ? "Finish" : "Next") { advance(skipped: false) }
                .buttonStyle(.borderedProminent).foregroundStyle(SupportTheme.onAccent).frame(minHeight: 48)
            Button("Skip this prompt") { advance(skipped: true) }.frame(minHeight: 44)
        }
        .disabled(isSaving).frame(maxWidth: .infinity).padding(16).background(SupportTheme.surface)
    }

    @ViewBuilder private func reflection(_ activity: SupportActivity) -> some View {
        Text(activity.status == .completed ? "Finished on this device" : "Activity stopped")
            .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if activity.kind == .grounding && activity.status == .completed {
            Text("Canonical completion and XP will be confirmed after account sync.")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
        }
        if let reflection = activity.reflection {
            Text("Your reflection: \(reflection.outcome.displayTitle.lowercased()).")
            Button("Talk about this") { showDiscussion() }.frame(minHeight: 44).disabled(isSaving)
            Button(returnTitle) { leave() }.buttonStyle(.borderedProminent).foregroundStyle(SupportTheme.onAccent).frame(minHeight: 48)
        } else {
            Text("How was that for you?").font(.title2).accessibilityAddTraits(.isHeader)
            TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...6).supportField()
                .focused($fieldFocused).disabled(isSaving)
            Toggle("Include my written answers in the conversation", isOn: $includeAnswers).disabled(isSaving)
            Text(includeAnswers ? "Only the written preview below may be included in later AI context for this session." : "This written preview stays out of automatic session context. Answers you sent in Chat remain in that conversation.")
                .font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
            if includeAnswers {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sharing preview").font(.headline)
                    Text(SupportActivityDiscussion.reflectionPreview(activity, note: note)).textSelection(.enabled)
                    Text("This preview is limited to 1,000 text units; emoji can count as two. Your full answers stay saved. Use Talk about this to choose other answers for a message.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach([SupportReflectionOutcome.helpful, .notForMe, .notSure, .skip], id: \.self) { outcome in
                Button(outcome.displayTitle) {
                    perform {
                        try await coordinator.reflect(activity.id, outcome: outcome, note: note, includeAnswers: includeAnswers)
                        if outcome != .skip { appState.celebrateCompletion(String(localized: "Reflection saved"), soft: true) }
                    }
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(isSaving || note.unicodeScalars.count > 1_000)
            }
        }
    }

    private var returnTitle: String {
        if case .chat = presentation.origin { return "Back to conversation" }
        return "Done for now"
    }

    private func loadAnswer() {
        guard let activity, let prompt else { return }
        answer = activity.step?.actionText ?? activity.checkpoint.responses[prompt.id] ?? ""
    }

    private func checkpoint(acknowledge: Bool = false, skipped: Bool = false) -> SupportCheckpoint? {
        guard let activity, let prompt else { return nil }
        var value = activity.checkpoint
        if skipped || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.responses[prompt.id] = nil }
        else { value.responses[prompt.id] = answer }
        if acknowledge {
            value.lastPromptID = prompt.id
            if skipped { value.skippedStepIDs.append(prompt.id) } else { value.completedStepIDs.append(prompt.id) }
        }
        if let activeSince { value.activeMilliseconds += Int64(max(0, Date().timeIntervalSince(activeSince)) * 1_000) }
        return value
    }

    private func scheduleSave() {
        guard !isSaving else { return }
        draftTask?.cancel()
        guard let activity, activity.status.isUnfinished, let prompt else { return }
        let stored = activity.step?.actionText ?? activity.checkpoint.responses[prompt.id] ?? ""
        guard answer != stored else { draftSavePending = false; return }
        draftSavePending = true
        if activity.kind == .chooseStep && answer.unicodeScalars.count > 400 {
            error = "Shorten this step to 400 characters to save it."
            return
        }
        draftTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let value = checkpoint() else { return }
                try await coordinator.checkpoint(presentation.id, value: value)
                activeSince = Date()
                draftSavePending = false
            } catch is CancellationError {} catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }

    private func showDiscussion() {
        draftTask?.cancel()
        perform {
            if let activity, activity.status.isUnfinished, let value = checkpoint() {
                try await coordinator.checkpoint(activity.id, value: value)
                activeSince = Date()
            }
            discussion = try coordinator.discussionSnapshot(activityID: presentation.id)
        }
    }

    private func advance(skipped: Bool) {
        guard let activity else { return }
        let last = promptIndex == activity.templateKey.prompts.count - 1
        perform {
            guard let value = checkpoint(acknowledge: true, skipped: skipped) else { return }
            if last {
                try await coordinator.finish(activity.id, checkpoint: value)
                // Skipping every prompt records "stopped", which is not celebrated.
                if coordinator.journal.activities[activity.id]?.status == .completed {
                    appState.celebrateCompletion(String(localized: "Activity finished"))
                }
            }
            else { try await coordinator.checkpoint(activity.id, value: value); loadAnswer(); headingFocused = true }
            activeSince = Date()
        }
    }

    private func pause() {
        perform {
            guard let activity else { return }
            if activity.kind == .chooseStep {
                // An unfinished editable step is a protected checkpoint, not a saved task or completion.
                var value = activity.checkpoint; value.responses["action"] = answer
                try await coordinator.pause(activity.id, checkpoint: value)
            } else if let value = checkpoint() { try await coordinator.pause(activity.id, checkpoint: value) }
            activeSince = nil
            dismiss()
        }
    }

    private func finish(stopped: String) {
        perform { try await coordinator.finish(presentation.id, checkpoint: checkpoint(), stoppedReason: stopped) }
    }

    private func choose(_ choice: SupportStepChoice) {
        perform {
            try await coordinator.chooseStep(presentation.id, choice: choice, text: answer)
            if choice == .didIt { appState.celebrateCompletion(String(localized: "Step done")) }
            if choice == .saveForLater { try await coordinator.doneForNow(presentation.sessionID); dismiss() }
        }
    }

    private func leave() {
        perform { try await coordinator.doneForNow(presentation.sessionID); dismiss() }
    }

    private func perform(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isSaving else { return }
        let precedingSave = draftTask; precedingSave?.cancel(); draftTask = nil
        isSaving = true; error = nil; needsRecoveryChoice = false
        Task { @MainActor in
            await precedingSave?.value
            defer { isSaving = false }
            do { try await body(); draftSavePending = false }
            catch {
                needsRecoveryChoice = (error as? SupportSessionError) == .recoveryCopiesNeedDecision
                self.error = SupportSessionCoordinator.message(for: error)
            }
        }
    }
}

extension SupportReflectionOutcome {
    var displayTitle: String {
        switch self {
        case .helpful: return "Helpful"
        case .notForMe: return "Not for me"
        case .notSure: return "Not sure"
        case .skip: return "Skip"
        }
    }
}

/// Starting another activity requires a choice about the selected unfinished work.
struct SupportActivityChoiceButton: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    let template: SupportActivityTemplateKey
    var sessionID: UUID?
    var origin: SupportEntryOrigin = .explore
    var title: String?
    @State private var pendingSession: UUID?
    @State private var showPreviousChoice = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Button(title ?? template.title) { start(previous: nil) }
            .frame(minHeight: 44, alignment: .leading)
            .disabled(isWorking)
            .confirmationDialog("An activity is still unfinished", isPresented: $showPreviousChoice, titleVisibility: .visible) {
                Button("Save it and start this activity") { start(previous: .saveAndPause) }
                Button("End it and start this activity", role: .destructive) { start(previous: .endPrevious) }
                Button("Keep current activity", role: .cancel) { pendingSession = nil }
            } message: {
                Text("Saving leaves the activity available to resume. Ending records that it stopped and does not award completion.")
            }
            .alert("Couldn’t start this activity", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Your saved work is still available.") }
    }

    private func start(previous: SupportPreviousActivityDisposition?) {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let selected: UUID
                if let sessionID { selected = sessionID }
                else if let pendingSession { selected = pendingSession }
                else if case .chat(let conversationID) = origin {
                    selected = try await coordinator.createSession(conversationID: conversationID).id
                } else { selected = try await coordinator.createSession().id }
                pendingSession = selected
                _ = try await coordinator.start(template, in: selected, origin: origin, previous: previous)
                pendingSession = nil
            } catch SupportSessionError.anotherActivityUnfinished {
                showPreviousChoice = true
            } catch { self.error = SupportSessionCoordinator.message(for: error) }
        }
    }
}
