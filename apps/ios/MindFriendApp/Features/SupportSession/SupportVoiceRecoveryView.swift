import SwiftUI

/// Local finals remain reachable even when their conversation was removed on another device.
struct SupportVoiceRecoveryLink: View {
    @ObservedObject var coordinator: SupportSessionCoordinator
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let count = coordinator.journal.transcriptEvents.filter { $0.syncState != .saved }.count
        if count > 0, coordinator.identity.ownerID == appState.currentUser?.id {
            NavigationLink {
                SupportVoiceRecoveryView(coordinator: coordinator, accountEpoch: appState.accountEpoch)
            } label: {
                Text("Voice turns on this device (\(count))").frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal).background(.regularMaterial)
        }
    }
}

struct SupportVoiceRecoveryView: View {
    @ObservedObject var coordinator: SupportSessionCoordinator
    let accountEpoch: UInt64
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var removing: SupportTranscriptEvent?
    @State private var error: String?

    private var current: Bool {
        coordinator.identity.ownerID == appState.currentUser?.id && appState.accountEpoch == accountEpoch
            && container.supportSessionCoordinator === coordinator
            && container.supportSessionAccountEpoch == accountEpoch
    }

    var body: some View {
        Group {
            if current {
                List {
                    Section {
                        Text("These voice turns have a copy on this device and have not been confirmed as saved to your account. A conversation removed elsewhere may no longer be available.")
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    ForEach(coordinator.journal.transcriptEvents.filter { $0.syncState != .saved }
                        .sorted { ($0.occurredAt, $0.sequence) < ($1.occurredAt, $1.sequence) }) { event in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(event.role == .user ? "You" : "MindFriend").font(.headline)
                            Text(event.text).textSelection(.enabled)
                            Text(event.syncState == .rejected ? "Not saved to account" : "Account sync pending").font(.caption)
                            Button("Copy voice turn") {
                                guard current else { return }
                                UIPasteboard.general.setObjects([event.text as NSString], localOnly: true,
                                    expirationDate: Date().addingTimeInterval(120))
                            }
                            if event.syncState == .rejected {
                                Button("Try saving again") { change(event, retry: true) }
                            }
                            Button("Remove local copy", role: .destructive) { removing = event }
                        }
                    }
                }
            } else { ContentUnavailableView("Account changed", systemImage: "person.crop.circle") }
        }
        .navigationTitle("Voice turns on this device")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove this local voice turn?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let event = removing {
                Button("Remove local copy", role: .destructive) { removing = nil; change(event, retry: false) }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Copy anything you want to keep first. An upload already in progress may still save an account copy.")
        }
    }

    private func change(_ event: SupportTranscriptEvent, retry: Bool) {
        guard current else { return }
        Task {
            do {
                guard current else { return }
                if retry {
                    try await coordinator.repository.retryRejectedTranscriptEvent(epoch: coordinator.identity.epochID, id: event.id)
                    if current { try await container.supportSync?.retry() }
                } else {
                    try await coordinator.repository.discardTranscriptEvents(epoch: coordinator.identity.epochID, ids: [event.id])
                }
            } catch {
                if current { self.error = SupportSessionCoordinator.message(for: error) }
            }
        }
    }
}
