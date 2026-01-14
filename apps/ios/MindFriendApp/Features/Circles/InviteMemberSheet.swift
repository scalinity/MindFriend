import SwiftUI

/// Sheet for inviting a new member to a circle via email or phone
struct InviteMemberSheet: View {
    let circleId: String
    let circleName: String
    let onInviteSent: (CircleInvite) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer

    @State private var contactType: ContactType = .email
    @State private var email = ""
    @State private var phone = ""
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""

    enum ContactType: String, CaseIterable {
        case email = "Email"
        case phone = "Phone"
    }

    var isValid: Bool {
        switch contactType {
        case .email:
            return email.contains("@") && email.contains(".")
        case .phone:
            return phone.count >= 10
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Contact method", selection: $contactType) {
                        ForEach(ContactType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if contactType == .email {
                        TextField("friend@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        TextField("Phone number", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }
                } header: {
                    Text("Who do you want to invite?")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("They'll receive an invitation to join \"\(circleName)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("If they don't have the app yet, they'll get instructions to download it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Invite") {
                        sendInvite()
                    }
                    .disabled(!isValid || isSending)
                }
            }
            .alert("Couldn't Send Invite", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func sendInvite() {
        guard isValid else { return }

        isSending = true

        Task {
            do {
                let invite = try await container.supabaseDataService.createCircleInvite(
                    circleId: circleId,
                    email: contactType == .email ? email : nil,
                    phone: contactType == .phone ? phone : nil
                )

                await MainActor.run {
                    onInviteSent(invite)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

/// Row displaying a pending invite
struct PendingInviteRow: View {
    let invite: CircleInvite

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: invite.sentAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
            }

            // Contact info
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.displayContact)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Invited \(timeAgo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Pending badge
            Text("Pending")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

/// Section showing all pending invites for a circle
struct PendingInvitesSection: View {
    let invites: [CircleInvite]

    var body: some View {
        if !invites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pending Invites")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(invites) { invite in
                        PendingInviteRow(invite: invite)
                            .padding(.horizontal)

                        if invite.id != invites.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    VStack {
        InviteMemberSheet(
            circleId: "test",
            circleName: "Wellness Squad",
            onInviteSent: { _ in }
        )

        PendingInviteRow(
            invite: CircleInvite(
                id: "1",
                circleId: "c1",
                inviterId: "u1",
                inviteeEmail: "friend@example.com",
                inviteePhone: nil,
                inviteCode: "ABC123",
                sentAt: Date().addingTimeInterval(-3600),
                acceptedAt: nil,
                reminderSentAt: nil,
                inviterName: nil,
                circleName: nil
            )
        )
        .padding()
    }
    .environmentObject(DependencyContainer())
}
