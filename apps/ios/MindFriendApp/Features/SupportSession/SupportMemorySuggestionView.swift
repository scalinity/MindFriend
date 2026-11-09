import SwiftUI

/// "Suggest memories from this session" (spec 8.4).
///
/// Two deliberate steps and nothing automatic:
///  1. A read-only PREVIEW lists the person's own messages from this session's conversation, exactly as they would be
///     sent. The person chooses which ones. Opening this screen loads that preview; it never reaches a model.
///  2. GENERATE is a separate, explicit button. It sends the chosen message IDs and the exact revisions that were
///     previewed (never message text). Results are review-only suggestions: they are not used as memory until saved in
///     "What MindFriend remembers", and they expire after seven days.
///
/// The request ID is created once per Generate tap and kept in `SupportMemorySuggestionModel` together with its immutable
/// body, so every retry sends the same bytes under the same ID and the server can never run the provider twice for it.
struct SupportMemorySuggestionView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    /// True when this screen was pushed from What MindFriend remembers: "Review" then simply returns to that list.
    var cameFromMemoryList = false
    @StateObject private var model = SupportMemorySuggestionModel()

    private var session: SupportSession? { coordinator.journal.sessions[sessionID] }

    /// Why the flow cannot start from this device right now. Never fabricates a session or conversation.
    private var unavailableReason: String? {
        guard let binding = container.supportSync?.cloud.binding,
              appState.currentUser?.id == coordinator.identity.ownerID,
              appState.accountEpoch == binding.accountEpoch,
              binding.ownerID == coordinator.identity.ownerID,
              container.supportSessionCoordinator === coordinator,
              container.supportSessionAccountEpoch == binding.accountEpoch else {
            return "This account’s session is no longer available. Return to your current account."
        }
        guard let session, session.status != .deleted else { return "This session is no longer on this device." }
        guard session.conversationID != nil else {
            return "This session has no conversation attached, so there is nothing to suggest memories from."
        }
        guard container.supportSync != nil else { return "Account sync isn’t available right now." }
        return nil
    }

    var body: some View {
        Form {
            if let reason = unavailableReason {
                Section { Text(reason) }
            } else {
                content
            }
        }
        .navigationTitle("Suggest memories")
        .supportCanvas()
        .task(id: "\(sessionID)|\(unavailableReason ?? "ready")") { await loadIfNeeded() }
    }

    // MARK: Content by phase

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loadingPreview:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading your messages. Nothing is sent to an AI service while you look.")
                }
            }
        case .preview, .sending:
            if let preview = model.preview { previewSections(preview) }
        case .pending:
            Section("Still working") {
                Text("Your account hasn’t confirmed the outcome yet. Checking again uses the same request and cannot start a second AI request for it.")
                Button("Check again") { send { await $0.retry(cloud: $1, isCurrent: $2) } }
                    .disabled(model.phase == .sending)
            }
        case .finished(let result):
            resultSections(result)
        case .stopped(let note):
            stoppedSections(note)
        case .unavailable(let text):
            Section {
                Text(text)
                // Only a preview that never produced a request may be reloaded here; a request is never abandoned.
                if model.request == nil { Button("Try again") { reload() } }
            }
        }
    }

    @ViewBuilder private func previewSections(_ preview: SupportMemorySuggestionPreview) -> some View {
        Section {
            Text("Choose the messages MindFriend may send to an AI service to look for things you clearly said about yourself. Only your own messages from this session’s conversation are listed. Nothing is sent until you choose Generate.")
            if preview.sessionIsClosed {
                Text("This session is closed. You can still choose messages from it.").foregroundStyle(.secondary)
            }
        }
        if coordinator.journal.personalizedCloudPaused {
            Section {
                Text("A privacy or context change on this device is still being confirmed with your account. Generating is paused until it is.")
            }
        }
        Section("Messages you can choose") {
            if preview.conversationSuppressed {
                Text("This conversation was excluded from future context, so nothing can be suggested from it.")
            } else if preview.messages.isEmpty {
                Text("No eligible messages of yours were found in this conversation.").foregroundStyle(.secondary)
            }
            ForEach(preview.messages) { message in messageRow(message, preview: preview) }
            if !preview.messages.isEmpty {
                Text(selectionSummary(preview)).font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Select as many as fit") { model.selectRecent(preview) }
                    Spacer()
                    Button("Clear") { model.clearSelection() }.disabled(model.selected.isEmpty)
                }
                .buttonStyle(.borderless)
            }
            if preview.excludedSuppressed > 0 || preview.excludedTooLong > 0 {
                Text(exclusionNote(preview)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("Exactly what the AI service receives") {
            Text("The selected messages above, shown as they will be sent (line breaks and some characters are simplified), together with these fixed instructions.")
                .font(.subheadline)
            DisclosureGroup("Instructions sent with your messages") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.disclosure.systemPrompt)
                    Text(preview.disclosure.instructions)
                }
                .font(.footnote)
                .textSelection(.enabled)
            }
            Text("Sent to \(providerName(preview.disclosure)) (\(preview.disclosure.providerModel)). We ask the provider not to store the request, but we can’t guarantee that, and anything already sent can’t be taken back.")
                .font(.subheadline)
            Text("Never sent: " + preview.disclosure.notSent.map(Self.readable).joined(separator: ", ") + ".")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        Section("What happens next") {
            Text("Suggestions appear under “Suggestions to review” in What MindFriend remembers. They are not used as memory until you save them, they only come from messages you chose, and they expire after 7 days if you don’t review them. This uses one AI request.")
        }
        Section {
            Button {
                send { await $0.generate(cloud: $1, isCurrent: $2) }
            } label: {
                HStack {
                    if model.phase == .sending { ProgressView() }
                    Text(model.phase == .sending ? "Generating…" : "Generate suggestions")
                }
            }
            .disabled(!canGenerate(preview))
            .accessibilityHint("Sends the selected messages to the AI service. Suggestions are only saved for your review.")
        }
    }

    @ViewBuilder private func resultSections(_ result: SupportMemorySuggestionResult) -> some View {
        Section {
            switch result.status {
            case .saved:
                Text(result.pendingReviewCount == 1 ? "1 suggestion is waiting for your review." : "\(result.pendingReviewCount) suggestions are waiting for your review.")
                    .font(.headline)
                if result.pendingReviewCount != result.savedCount {
                    Text("This request originally saved \(result.savedCount). Some have since been approved, dismissed, expired, or removed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("They aren’t used as memory until you save them. Suggestions you don’t review expire after 7 days.")
                if result.skippedCount > 0 {
                    Text("\(result.skippedCount) more matched something you already have or dismissed, so they were left unchanged.")
                        .foregroundStyle(.secondary)
                }
                if cameFromMemoryList {
                    Button("Review suggestions") {
                        Task { @MainActor in
                            try? await container.supportSync?.refreshMemory()
                            dismiss()
                        }
                    }
                } else {
                    // SupportMemoryView refreshes the account snapshot when it appears.
                    NavigationLink("Review in What MindFriend remembers") { SupportMemoryView() }
                }
            case .noCandidates:
                Text("No suggestions were added.").font(.headline)
                Text(result.skippedCount > 0
                     ? "Everything found matched something you already have or dismissed, so it was left unchanged."
                     : "Nothing in the messages you chose was clearly stated as a fact about you. Nothing was saved.")
            case .failed:
                Text("The AI service didn’t produce usable suggestions.").font(.headline)
                Text("Nothing was saved. You can start a new request; that uses another AI request.")
            case .stale:
                Text("Your messages or privacy settings changed while the AI service was working.").font(.headline)
                Text("The result was discarded. Nothing was saved.")
            case .unknown:
                Text("We couldn’t confirm what happened with that request.").font(.headline)
                Text("Nothing is shown as saved. If suggestions were created they will appear in What MindFriend remembers. Starting a new request uses another AI request.")
            case .notStarted:
                Text("That request never reached the AI service. Nothing was sent or saved.").font(.headline)
            case .pending:
                Text("Your account hasn’t confirmed the outcome yet.")
            }
        }
        if result.status != .saved {
            Section {
                Button("Choose messages again") { reload() }
            }
        }
    }

    @ViewBuilder private func stoppedSections(_ note: SupportMemorySuggestionModel.StopNote) -> some View {
        Section {
            Text(note.title).font(.headline)
            Text(note.detail)
            if note.mayHaveReachedService {
                Text("Sending the same request again is safe: it never starts a second AI request for the same one.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if note.canRetrySameRequest {
                Button("Try again with the same request") { send { await $0.retry(cloud: $1, isCurrent: $2) } }
                    .disabled(model.phase == .sending)
            }
            if note.needsFreshPreview {
                Button("Choose messages again") { reload() }
            }
        }
    }

    // MARK: Rows and copy

    private func messageRow(_ message: SupportMemorySuggestionMessage, preview: SupportMemorySuggestionPreview) -> some View {
        let isOn = model.selected.contains(message.id)
        return Toggle(isOn: Binding(
            get: { model.selected.contains(message.id) },
            set: { model.setSelected(message.id, $0, preview: preview) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let date = message.createdAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("memory-source-" + message.id.uuidString.lowercased())
        .disabled(model.phase == .sending || (!isOn && !model.canAdd(message, preview: preview)))
    }

    private func selectionSummary(_ preview: SupportMemorySuggestionPreview) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(model.selectedBytes(preview)), countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: Int64(min(preview.maxTotalBytes, SupportMemorySuggestionLimits.maxSelectedBytes)), countStyle: .file)
        let most = min(preview.maxMessages, SupportMemorySuggestionLimits.maxSelectedMessages)
        return "\(model.selected.count) of up to \(most) selected · \(bytes) of \(limit)"
    }

    private func exclusionNote(_ preview: SupportMemorySuggestionPreview) -> String {
        var parts: [String] = []
        if preview.excludedSuppressed > 0 { parts.append("\(preview.excludedSuppressed) excluded because you asked MindFriend to stop using them") }
        if preview.excludedTooLong > 0 { parts.append("\(preview.excludedTooLong) too long to send") }
        return "Not listed: " + parts.joined(separator: "; ") + "."
    }

    private func providerName(_ disclosure: SupportMemorySuggestionDisclosure) -> String {
        disclosure.providerVendor.lowercased() == "openai" ? "OpenAI" : disclosure.providerVendor.capitalized
    }

    private static func readable(_ key: String) -> String {
        switch key {
        case "assistant_replies": return "MindFriend’s replies"
        case "other_conversations": return "other conversations"
        case "health_data": return "Health data"
        case "private_vault": return "your private journal"
        case "unshared_activity_notes": return "activity notes you haven’t shared"
        case "saved_memories": return "saved memories"
        default: return key.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func canGenerate(_ preview: SupportMemorySuggestionPreview) -> Bool {
        model.phase == .preview && !model.selected.isEmpty && !preview.conversationSuppressed
            && !coordinator.journal.personalizedCloudPaused
            && model.selectedBytes(preview) <= min(preview.maxTotalBytes, SupportMemorySuggestionLimits.maxSelectedBytes)
    }

    // MARK: Actions (every awaited step re-checks owner and account epoch)

    /// Everything that must still hold after an await: same repository identity, same account binding, session still here.
    private func currentCheck(identity: SupportSessionIdentity, binding: SupportCloudBinding) -> @MainActor () -> Bool {
        let container = self.container, coordinator = self.coordinator, appState = self.appState, sessionID = self.sessionID
        return { [weak container, weak coordinator, weak appState] in
            guard let container, let coordinator, let appState,
                  let session = coordinator.journal.sessions[sessionID], session.status != .deleted else { return false }
            return coordinator.identity == identity
                && container.supportSessionCoordinator === coordinator
                && container.supportSync?.cloud.binding == binding
                && appState.currentUser?.id == binding.ownerID && appState.accountEpoch == binding.accountEpoch
                && container.supportSessionAccountEpoch == binding.accountEpoch
        }
    }

    private func loadIfNeeded() async {
        guard unavailableReason == nil, model.phase == .idle, let cloud = container.supportSync?.cloud else { return }
        await model.loadPreview(sessionID: sessionID, cloud: cloud,
                                isCurrent: currentCheck(identity: coordinator.identity, binding: cloud.binding))
    }

    private func reload() {
        guard let cloud = container.supportSync?.cloud else { return }
        let check = currentCheck(identity: coordinator.identity, binding: cloud.binding)
        let id = sessionID
        // Not tied to this view's lifetime: leaving the screen must not cancel a request that may already be running.
        Task { @MainActor in await model.loadPreview(sessionID: id, cloud: cloud, isCurrent: check) }
    }

    private func send(_ action: @escaping @MainActor (SupportMemorySuggestionModel, SupportSessionCloudService, @MainActor () -> Bool) async -> Void) {
        guard unavailableReason == nil, let cloud = container.supportSync?.cloud else { return }
        let check = currentCheck(identity: coordinator.identity, binding: cloud.binding)
        let model = self.model
        Task { @MainActor in await action(model, cloud, check) }
    }
}

/// State of one suggestion flow. Owns the stable request ID and immutable request body.
@MainActor
final class SupportMemorySuggestionModel: ObservableObject {
    /// What the person can do next, with copy that never claims more than is known.
    struct StopNote: Equatable {
        let title: String
        let detail: String
        /// The request may already have reached the service; re-sending the SAME request is safe, a new one is not offered.
        let mayHaveReachedService: Bool
        let canRetrySameRequest: Bool
        let needsFreshPreview: Bool
    }

    enum Phase: Equatable {
        case idle
        case loadingPreview
        case preview
        case sending
        /// The server has not confirmed an outcome; a lost commit acknowledgement may already have saved candidates.
        case pending
        case finished(SupportMemorySuggestionResult)
        case stopped(StopNote)
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var preview: SupportMemorySuggestionPreview?
    @Published private(set) var selected: Set<UUID> = []
    /// Created at the explicit Generate tap and never rebuilt for retries.
    private(set) var request: SupportMemorySuggestionRequest?

    // MARK: Selection (deliberate: nothing is selected by default)

    func selectedBytes(_ preview: SupportMemorySuggestionPreview) -> Int {
        preview.messages.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.utf8Bytes }
    }

    func canAdd(_ message: SupportMemorySuggestionMessage, preview: SupportMemorySuggestionPreview) -> Bool {
        guard !selected.contains(message.id) else { return true }
        return selected.count < min(preview.maxMessages, SupportMemorySuggestionLimits.maxSelectedMessages)
            && selectedBytes(preview) + message.utf8Bytes <= min(preview.maxTotalBytes, SupportMemorySuggestionLimits.maxSelectedBytes)
    }

    func setSelected(_ id: UUID, _ on: Bool, preview: SupportMemorySuggestionPreview) {
        guard phase == .preview, let message = preview.messages.first(where: { $0.id == id }) else { return }
        if on { if canAdd(message, preview: preview) { selected.insert(id) } } else { selected.remove(id) }
    }

    /// Newest first until a limit is reached. An explicit button, never a default.
    func selectRecent(_ preview: SupportMemorySuggestionPreview) {
        guard phase == .preview else { return }
        selected = []
        for message in preview.messages.reversed() where canAdd(message, preview: preview) { selected.insert(message.id) }
    }

    func clearSelection() { if phase == .preview { selected = [] } }

    // MARK: Preview (read only)

    func loadPreview(sessionID: UUID, cloud: SupportSessionCloudService, isCurrent: @MainActor () -> Bool) async {
        // A request that may be running is never abandoned by reloading: only a definite end, or a request
        // that was never built, may be replaced.
        switch phase {
        case .loadingPreview, .sending: return
        case .pending: return
        case .stopped(let note) where request != nil && note.mayHaveReachedService: return
        default: break
        }
        phase = .loadingPreview
        do {
            let value = try await cloud.prepareMemorySuggestions(sessionID: sessionID)
            guard isCurrent(), value.binding == cloud.binding else { phase = .unavailable(Self.accountChanged); return }
            preview = value
            selected = []
            request = nil
            phase = .preview
        } catch {
            guard isCurrent() else { phase = .unavailable(Self.accountChanged); return }
            preview = nil
            phase = Self.describePreviewFailure(error)
        }
    }

    // MARK: Generate (explicit)

    func generate(cloud: SupportSessionCloudService, isCurrent: @MainActor () -> Bool) async {
        guard phase == .preview, let preview, !selected.isEmpty, isCurrent() else { return }
        let built: SupportMemorySuggestionRequest
        do {
            built = try SupportMemorySuggestionRequest(preview: preview, selecting: selected, requestID: UUID())
        } catch {
            phase = Self.describeSendFailure(error)
            return
        }
        request = built          // the stable ID and body for every retry of this Generate
        await send(built, cloud: cloud, isCurrent: isCurrent)
    }

    /// Re-send the SAME request. Safe by construction: the server replays or reports pending, never a second provider call.
    func retry(cloud: SupportSessionCloudService, isCurrent: @MainActor () -> Bool) async {
        guard let request else { return }
        switch phase {
        case .pending, .stopped: break
        default: return
        }
        await send(request, cloud: cloud, isCurrent: isCurrent)
    }

    private func send(_ request: SupportMemorySuggestionRequest, cloud: SupportSessionCloudService,
                      isCurrent: @MainActor () -> Bool) async {
        guard isCurrent(), request.binding == cloud.binding else { phase = .unavailable(Self.accountChanged); return }
        phase = .sending
        do {
            let result = try await cloud.generateMemorySuggestions(request)
            // A reply that arrives after the account changed is never shown.
            guard isCurrent() else { phase = .unavailable(Self.accountChanged); return }
            phase = result.status == .pending ? .pending : .finished(result)
        } catch {
            guard isCurrent() else { phase = .unavailable(Self.accountChanged); return }
            phase = Self.describeSendFailure(error)
        }
    }

    // MARK: Honest copy

    private static let accountChanged = "The signed-in account changed, so nothing from this request is shown."

    static func describePreviewFailure(_ error: Error) -> Phase {
        guard let error = error as? SupportCloudError else { return .unavailable("Your messages couldn’t be loaded.") }
        switch error {
        case .rejected(let r):
            switch r.code {
            case .notFound:
                return .unavailable("Your account doesn’t have this session yet. Wait for sync to finish, then try again.")
            case .contentUnavailable:
                return .unavailable("This session has no conversation your account can use for suggestions.")
            default:
                return .unavailable("Your messages couldn’t be loaded.")
            }
        case .authenticationRequired: return .unavailable("Sign in again to load your messages.")
        case .capabilityUnavailable: return .unavailable("Memory suggestions aren’t available from the service yet.")
        case .transport, .serverTemporary, .malformedResponse, .cancelled, .ownerChanged, .invalidRequest, .transcriptTargetPending:
            return .unavailable("Your messages couldn’t be loaded right now. Nothing was sent to an AI service. Try again later.")
        }
    }

    static func describeSendFailure(_ error: Error) -> Phase {
        guard let error = error as? SupportCloudError else {
            return .stopped(.init(title: "We couldn’t confirm that request.", detail: "Nothing is shown as saved.",
                                  mayHaveReachedService: true, canRetrySameRequest: true, needsFreshPreview: false))
        }
        switch error {
        case .rejected(let r):
            return .stopped(rejection(r))
        case .invalidRequest:
            return .stopped(.init(title: "That selection can’t be sent.", detail: "Nothing was sent. Choose fewer or shorter messages.",
                                  mayHaveReachedService: false, canRetrySameRequest: false, needsFreshPreview: true))
        case .authenticationRequired:
            return .stopped(.init(title: "Sign in again to continue.", detail: "Your request is kept so you can retry it after signing in.",
                                  mayHaveReachedService: false, canRetrySameRequest: true, needsFreshPreview: false))
        case .capabilityUnavailable:
            return .stopped(.init(title: "Memory suggestions aren’t available from the service yet.", detail: "Your request is kept for retry.",
                                  mayHaveReachedService: false, canRetrySameRequest: true, needsFreshPreview: false))
        case .ownerChanged:
            return .unavailable(accountChanged)
        case .serverTemporary(_, let retryAfter):
            let wait = retryAfter.map { " Try again in about \(Int($0.rounded(.up))) seconds." } ?? ""
            return .stopped(.init(title: "The service is busy or couldn’t finish.",
                                  detail: "We couldn’t confirm whether the request started, so nothing is shown as saved.\(wait)",
                                  mayHaveReachedService: true, canRetrySameRequest: true, needsFreshPreview: false))
        case .transport, .malformedResponse, .cancelled, .transcriptTargetPending:
            return .stopped(.init(title: "We couldn’t confirm that request.",
                                  detail: "The connection ended before we got an answer, so nothing is shown as saved. Suggestions that were created appear in What MindFriend remembers.",
                                  mayHaveReachedService: true, canRetrySameRequest: true, needsFreshPreview: false))
        }
    }

    private static func rejection(_ r: SupportCloudRejection) -> StopNote {
        let reason = r.message ?? ""
        switch r.code {
        case .privacyRevisionStale:
            return .init(title: "Your messages or privacy settings changed.", detail: "Nothing was sent. Choose your messages again.",
                         mayHaveReachedService: false, canRetrySameRequest: false, needsFreshPreview: true)
        case .entitlementRequired:
            return .init(title: "You’ve reached today’s AI limit.", detail: "Nothing was sent. You can try again after the limit resets.",
                         mayHaveReachedService: false, canRetrySameRequest: true, needsFreshPreview: false)
        case .contentUnavailable where reason == "personalization_off":
            return .init(title: "Memory suggestions are off for your account.",
                         detail: "Your privacy setting keeps saved personal context off, so nothing was sent. You can change it in settings.",
                         mayHaveReachedService: false, canRetrySameRequest: true, needsFreshPreview: false)
        case .contentUnavailable, .notFound, .invalidPayload:
            return .init(title: "Those messages can’t be used.", detail: "Nothing was sent. They may have changed, been removed, or not finished syncing.",
                         mayHaveReachedService: false, canRetrySameRequest: false, needsFreshPreview: true)
        case .operationIDReused:
            return .init(title: "That request was already used for a different selection.", detail: "Nothing new was sent.",
                         mayHaveReachedService: false, canRetrySameRequest: false, needsFreshPreview: true)
        default:
            return .init(title: "The request wasn’t accepted.", detail: "Nothing was sent.",
                         mayHaveReachedService: false, canRetrySameRequest: false, needsFreshPreview: true)
        }
    }
}
