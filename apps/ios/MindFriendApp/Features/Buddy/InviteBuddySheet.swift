import SwiftUI

/// Sheet for inviting a buddy after onboarding
struct InviteBuddySheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var contactMethod: BuddyRelationship.InviteMethod = .sms
    @State private var contact = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var inviteCode: String?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                        .padding(.top, 24)
                        .accessibilityHidden(true)

                    // Header
                    VStack(spacing: 12) {
                        Text("Invite a Wellness Buddy")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Invite a friend to join your wellness journey. You'll be able to see each other's streaks and send encouragement!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    // Stats row
                    HStack(spacing: 24) {
                        StatBadge(value: "3x", label: "more likely\nto succeed")
                        StatBadge(value: "+100", label: "XP for\nboth of you")
                    }
                    .padding(.vertical, 8)

                    // Method picker
                    Picker("Contact Method", selection: $contactMethod) {
                        Text("Text Message").tag(BuddyRelationship.InviteMethod.sms)
                        Text("Email").tag(BuddyRelationship.InviteMethod.email)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    // Contact input
                    VStack(alignment: .leading, spacing: 8) {
                        Text(contactMethod == .sms ? "Phone Number" : "Email Address")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(
                            contactMethod == .sms ? "Enter phone number" : "Enter email address",
                            text: $contact
                        )
                        .textFieldStyle(.plain)
                        .keyboardType(contactMethod == .sms ? .phonePad : .emailAddress)
                        .textContentType(contactMethod == .sms ? .telephoneNumber : .emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .accessibilityLabel(contactMethod == .sms ? "Phone number input" : "Email address input")
                    }
                    .padding(.horizontal, 24)

                    // Send button
                    Button(action: sendInvite) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 4)
                            }
                            Text(isSending ? "Sending..." : "Send Invite")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canSend)
                    .padding(.horizontal, 24)
                    .accessibilityLabel("Send invite")
                    .accessibilityHint(canSend ? "Send an invite to your buddy" : "Enter a valid contact first")

                    // How it works section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How it works")
                            .font(.headline)

                        HowItWorksRow(number: "1", text: "Your friend receives your invitation")
                        HowItWorksRow(number: "2", text: "They download MindFriend and sign up")
                        HowItWorksRow(number: "3", text: "You become wellness buddies!")
                    }
                    .padding(20)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Invite Buddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Invite Sent!", isPresented: $showSuccess) {
                Button("Copy Code") {
                    if let code = inviteCode {
                        UIPasteboard.general.string = code
                    }
                    dismiss()
                }
                Button("Done") {
                    dismiss()
                }
            } message: {
                if let code = inviteCode {
                    Text("Your buddy will receive an invitation. Share this code if needed: \(code)")
                } else {
                    Text("Your buddy will receive an invitation to join you!")
                }
            }
            .alert("Unable to Send", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var canSend: Bool {
        !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func sendInvite() {
        guard canSend else { return }
        isSending = true

        Task {
            do {
                let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
                let relationship = try await container.supabaseDataService.createBuddyInvite(
                    contact: trimmedContact,
                    method: contactMethod
                )

                await MainActor.run {
                    isSending = false
                    inviteCode = relationship.inviteCode
                    showSuccess = true
                }

                Analytics.shared.track(.buddyInviteSent, properties: [
                    "method": contactMethod.rawValue,
                    "source": "home_sheet"
                ])
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Could not send invite. Please check the contact and try again."
                    showError = true
                }
                error.report(context: ["action": "send_buddy_invite", "source": "home_sheet"])
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.tint)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct HowItWorksRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .cornerRadius(10)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

#Preview {
    InviteBuddySheet()
        .environmentObject(DependencyContainer())
}
