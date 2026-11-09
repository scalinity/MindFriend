import SwiftUI

struct FamilyManagementView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var showInviteSheet = false
    @State private var isLoading = true
    @State private var showRemoveConfirm = false
    @State private var memberToRemove: FamilyMember?
    @State private var error: Error?
    @State private var showError = false
    @State private var loadTask: Task<Void, Never>?

    private var billingService: BillingService {
        container.billingService
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if billingService.familyGroup == nil {
                    noFamilyGroupView
                } else {
                    familyContentView
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Family Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Close")
                }
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showInviteSheet) {
                FamilyPlanInviteSheet()
            }
            .alert("Remove Member", isPresented: $showRemoveConfirm, presenting: memberToRemove) { member in
                Button("Remove", role: .destructive) {
                    removeMember(member)
                }
                Button("Cancel", role: .cancel) {}
            } message: { member in
                Text(
                    "Remove \(member.displayName ?? member.invitedEmail ?? "this member") from your family plan? They will lose premium access."
                )
            }
            .alert("Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - No Family Group

    private var noFamilyGroupView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No Family Plan")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text("Upgrade to a Couples or Family plan to share premium access with your loved ones.")
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                dismiss()
            } label: {
                Text("View Plans")
            }
            .buttonStyle(.supportPrimary)
        }
        .padding()
    }

    // MARK: - Family Content

    private var familyContentView: some View {
        List {
            // Header Section
            Section {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    if let group = billingService.familyGroup {
                        Text(group.name)
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.semibold)

                        if billingService.isFamilyAdmin {
                            Label("You're the admin", systemImage: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                        }
                    }

                    if let sub = billingService.subscription {
                        HStack {
                            Text("Seats:")
                                .foregroundStyle(SupportTheme.textSecondary)
                            Text("\(sub.seatsUsed) / \(sub.seatsTotal)")
                                .fontWeight(.medium)

                            Spacer()

                            if sub.availableSeats > 0 {
                                Text("\(sub.availableSeats) available")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.accent)
                            } else {
                                Text("Full")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.accent)
                            }
                        }
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.xxs)
            }

            .listRowBackground(SupportTheme.surface)

            // Members Section
            Section {
                ForEach(billingService.familyMembers) { member in
                    MemberRow(
                        member: member,
                        isCurrentUser: member.userId == billingService.familyGroup?.adminUserId,
                        canRemove: billingService.isFamilyAdmin
                            && member.userId != billingService.familyGroup?.adminUserId,
                        onRemove: {
                            memberToRemove = member
                            showRemoveConfirm = true
                        }
                    )
                }
            } header: {
                HStack {
                    Text("Members")
                    Spacer()
                    Text("\(billingService.familyMembers.count)")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            .listRowBackground(SupportTheme.surface)

            // Invite Section (Admin only)
            if billingService.isFamilyAdmin {
                Section {
                    if let sub = billingService.subscription, sub.availableSeats > 0 {
                        Button {
                            showInviteSheet = true
                        } label: {
                            Label("Invite Member", systemImage: "person.badge.plus")
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SupportTheme.accent)
                            Text("All seats are filled")
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                } footer: {
                    Text("Invited members will receive a code to join your plan and gain premium access.")
                }
                .listRowBackground(SupportTheme.surface)
            }

            // Pending Invitations (Admin only)
            if billingService.isFamilyAdmin {
                Section {
                    PendingInvitationsView()
                } header: {
                    Text("Pending Invitations")
                }
                .listRowBackground(SupportTheme.surface)
            }
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Actions

    private func loadData() async {
        // P3-P4: Cancel any previous load to prevent race conditions
        loadTask?.cancel()

        loadTask = Task {
            isLoading = true
            defer { isLoading = false }

            // Check for cancellation before each async operation
            guard !Task.isCancelled else { return }
            await billingService.loadFamilyGroup()

            guard !Task.isCancelled else { return }
            await billingService.loadFamilyMembers()
        }

        await loadTask?.value
    }

    private func removeMember(_ member: FamilyMember) {
        Task {
            do {
                try await billingService.removeFamilyMember(memberId: member.id)
            } catch {
                await MainActor.run {
                    self.error = error
                    showError = true
                }
            }
        }
    }
}

// MARK: - Member Row

struct MemberRow: View {
    let member: FamilyMember
    let isCurrentUser: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Avatar
            ZStack {
                Circle()
                    .fill(SupportTheme.accent.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(initials)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SupportTheme.accent)
            }

            // Info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Text(member.displayName ?? member.invitedEmail ?? "Member")
                        .font(.body)

                    if isCurrentUser {
                        Text("(Admin)")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                    }
                }

                if let handle = member.handle {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            // Status indicator
            statusIndicator

            // Remove button
            if canRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Close")
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }

    private var initials: String {
        if let name = member.displayName, !name.isEmpty {
            let components = name.components(separatedBy: " ")
            let first = components.first?.first.map(String.init) ?? ""
            let last = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
            return (first + last).uppercased()
        }
        return "?"
    }

    private var statusText: String {
        switch member.status {
        case .pending: return "Invitation sent"
        case .active: return joinedText
        case .removed: return "Removed"
        }
    }

    private var joinedText: String {
        if let joinedAt = member.joinedAt {
            return "Joined \(joinedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Active"
    }

    private var statusColor: Color {
        switch member.status {
        case .pending: return SupportTheme.accent
        case .active: return SupportTheme.accent
        case .removed: return SupportTheme.textSecondary
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch member.status {
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(SupportTheme.accent)
                .font(.caption)
        case .active:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SupportTheme.accent)
                .font(.caption)
        case .removed:
            EmptyView()
        }
    }
}

// MARK: - Family Plan Invite Sheet

struct FamilyPlanInviteSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var sendEmail = true
    @State private var isLoading = false
    @State private var inviteResponse: SendInviteResponse?
    @State private var error: String?
    @State private var isCodeRevealed = false
    @State private var showCopiedFeedback = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                if let response = inviteResponse {
                    // Success state
                    inviteSuccessView(response: response)
                } else {
                    // Input state
                    inviteInputView
                }
            }
            .padding()
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Input View

    private var inviteInputView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(SupportTheme.accent)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Invite to Your Plan")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.semibold)

                Text("Enter the email address of the person you'd like to invite.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                TextField("Email address", text: $email)
                    .supportField()
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("Send invitation email", isOn: $sendEmail)
                    .font(.subheadline)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                sendInvite()
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(SupportTheme.textPrimary)
                } else {
                    Text("Send Invitation")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isValidEmail ? SupportTheme.accent : SupportTheme.textSecondary)
            .foregroundStyle(SupportTheme.onAccent)
            .cornerRadius(SupportTheme.controlRadius)
            .disabled(!isValidEmail || isLoading)

            Spacer()
        }
    }

    // MARK: - Success View

    private func inviteSuccessView(response: SendInviteResponse) -> some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent)

            Text("Invitation Created!")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text(response.message)
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            // Invite Code Display with tap-to-reveal (P3-S6)
            if let inviteCode = response.inviteCode {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("Invite Code")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if isCodeRevealed {
                        Text(inviteCode)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(SupportTheme.accent)
                            .supportCard()
                            .accessibilityLabel("Invite code: \(inviteCode)")

                        Button {
                            UIPasteboard.general.string = inviteCode
                            showCopiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedFeedback = false
                            }
                        } label: {
                            Label(
                                showCopiedFeedback ? "Copied!" : "Copy Code",
                                systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                            )
                            .font(.subheadline)
                        }
                    } else {
                        Button {
                            isCodeRevealed = true
                        } label: {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "eye.fill")
                                Text("Tap to reveal code")
                            }
                            .font(.headline)
                            .foregroundStyle(SupportTheme.accent)
                            .supportCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reveal invite code")
                    }
                }
            }

            // Expiry info
            if let expiresAtStr = response.expiresAt,
                let expiresAt = ISO8601DateFormatter().date(from: expiresAtStr)
            {
                Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
    }

    // MARK: - Helpers

    private var isValidEmail: Bool {
        let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        return email.wholeMatch(of: emailRegex) != nil
    }

    private func sendInvite() {
        isLoading = true
        error = nil

        Task {
            do {
                let response = try await container.billingService.inviteFamilyMember(
                    email: email,
                    sendEmail: sendEmail
                )
                await MainActor.run {
                    inviteResponse = response
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Pending Invitations View

struct PendingInvitationsView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var invitations: [FamilyInvitation] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var revealedCodes: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if loadError != nil {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(SupportTheme.accent)
                    Text("Failed to load invitations")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Button("Retry") {
                        Task { await loadInvitations() }
                    }
                    .font(.caption)
                }
            } else if invitations.isEmpty {
                Text("No pending invitations")
                    .foregroundStyle(SupportTheme.textSecondary)
                    .font(.subheadline)
            } else {
                ForEach(invitations) { invitation in
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(invitation.email)
                                .font(.subheadline)

                            if !invitation.isExpired {
                                Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            } else {
                                Text("Expired")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()

                        // P3-S6: Tap-to-reveal invite codes (security)
                        if revealedCodes.contains(invitation.id) {
                            Text(invitation.inviteCode)
                                .font(.caption.monospaced())
                                .foregroundStyle(SupportTheme.textSecondary)
                                .onTapGesture {
                                    UIPasteboard.general.string = invitation.inviteCode
                                }
                        } else {
                            Button {
                                revealedCodes.insert(invitation.id)
                            } label: {
                                Text("Tap to reveal")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task {
            await loadInvitations()
        }
    }

    private func loadInvitations() async {
        isLoading = true
        loadError = nil
        do {
            invitations = try await container.billingService.getPendingInvitations()
        } catch {
            loadError = error
        }
        isLoading = false
    }
}

#Preview {
    FamilyManagementView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
