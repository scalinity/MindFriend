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
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Icon
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                        .padding(.top, SupportTheme.Spacing.l)
                        .accessibilityHidden(true)

                    // Header
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Invite a Wellness Buddy")
                            .font(.title2)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Invite a friend to share wellness activities and send each other encouragement.")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, SupportTheme.Spacing.l)

                    // Stats row
                    HStack(spacing: SupportTheme.Spacing.l) {
                        BuddyStatBadge(value: "3x", label: "more likely\nto succeed")
                        BuddyStatBadge(value: "+100", label: "XP for\nboth of you")
                    }
                    .padding(.vertical, SupportTheme.Spacing.xs)

                    // Method picker
                    Picker("Contact Method", selection: $contactMethod) {
                        Text("Text Message").tag(BuddyRelationship.InviteMethod.sms)
                        Text("Email").tag(BuddyRelationship.InviteMethod.email)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, SupportTheme.Spacing.l)

                    // Contact input
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text(contactMethod == .sms ? "Phone Number" : "Email Address")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)

                        TextField(
                            contactMethod == .sms ? "Enter phone number" : "Enter email address",
                            text: $contact
                        )
                        .supportField()
                        .textFieldStyle(.plain)
                        .keyboardType(contactMethod == .sms ? .phonePad : .emailAddress)
                        .textContentType(contactMethod == .sms ? .telephoneNumber : .emailAddress)
                        .autocapitalization(.none)
                        .accessibilityLabel(contactMethod == .sms ? "Phone number input" : "Email address input")
                    }
                    .padding(.horizontal, SupportTheme.Spacing.l)

                    // Send button
                    Button(action: sendInvite) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.onAccent))
                                    .padding(.trailing, SupportTheme.Spacing.xxs)
                            }
                            Text(isSending ? "Sending..." : "Send Invite")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(!canSend)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .accessibilityLabel("Send invite")
                    .accessibilityHint(canSend ? "Send an invite to your buddy" : "Enter a valid contact first")

                    // How it works section
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                        Text("How it works")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        HowItWorksRow(number: "1", text: "Your friend receives your invitation")
                        HowItWorksRow(number: "2", text: "They download MindFriend and sign up")
                        HowItWorksRow(number: "3", text: "You become wellness buddies!")
                    }
                    .padding(SupportTheme.Spacing.l)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.cardRadius)
                    .padding(.horizontal, SupportTheme.Spacing.l)

                    Spacer(minLength: 32)
                }
            }
            .dismissKeyboardOnSwipe()
            .onTapGesture {
                hideKeyboard()
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportSheet()
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

private struct BuddyStatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.tint)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct HowItWorksRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(SupportTheme.textPrimary)
                .frame(width: 20, height: 20)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary)

            Spacer()
        }
    }
}

#Preview {
    InviteBuddySheet()
        .environmentObject(DependencyContainer())
}
