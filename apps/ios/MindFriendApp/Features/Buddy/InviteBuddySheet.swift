import MessageUI
import SwiftUI

/// Sheet for inviting a buddy after onboarding
struct InviteBuddySheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var contactMethod: BuddyRelationship.InviteMethod = .sms
    @State private var contact = ""
    @State private var isSending = false
    @State private var inviteCode: String?
    @State private var composer: BuddyInviteComposer?
    @State private var outcome: BuddyInviteOutcome?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinMessage: String?

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

                        HowItWorksRow(number: "1", text: "You send your invite from your own phone")
                        HowItWorksRow(number: "2", text: "Your friend opens the link or enters your code")
                        HowItWorksRow(number: "3", text: "You become wellness buddies!")
                    }
                    .padding(SupportTheme.Spacing.l)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.cardRadius)
                    .padding(.horizontal, SupportTheme.Spacing.l)

                    // Joining a friend who invited you
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Have a code from a friend?")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        TextField("Buddy code", text: $joinCode)
                            .supportField()
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Buddy code")
                        Button(action: joinBuddy) {
                            Text(isJoining ? "Joining..." : "Join my friend")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.supportPrimary)
                        .disabled(!canJoin)
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
            .sheet(item: $composer) { composer in
                composer.view { result in
                    self.composer = nil
                    outcome = result
                }
                .ignoresSafeArea()
            }
            .alert(item: $outcome) { outcome in
                switch outcome {
                case .sent(let code):
                    return Alert(
                        title: Text("Invite sent"),
                        message: Text("Your friend can tap the link or enter your code \(code) in MindFriend."),
                        dismissButton: .default(Text("Done")) { dismiss() })
                case .notSent(let code):
                    return Alert(
                        title: Text("Your invite wasn't sent"),
                        message: Text("Your code is \(code). You can share it another way, and it stays good for 30 days."),
                        primaryButton: .default(Text("Share code")) {
                            DispatchQueue.main.async { self.composer = .share(BuddyInviteMessage.body(code: code)) }
                        },
                        secondaryButton: .cancel(Text("Not now")))
                }
            }
            .alert("You're buddies now", isPresented: Binding(get: { joinMessage != nil }, set: { if !$0 { joinMessage = nil } })) {
                Button("Done") { dismiss() }
            } message: {
                Text(joinMessage ?? "")
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

    private var canJoin: Bool {
        joinCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 && !isJoining
    }

    /// Creates the invite (one record, one code), then sends it from this phone. "Sent" is shown
    /// only when Messages or Mail reports the message went out.
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
                let code = relationship.inviteCode
                await MainActor.run {
                    isSending = false
                    inviteCode = code
                    composer = BuddyInviteComposer.make(method: contactMethod, contact: trimmedContact, code: code)
                }

                Analytics.shared.track(.buddyInviteSent, properties: [
                    "method": contactMethod.rawValue,
                    "source": "home_sheet"
                ])
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "We couldn't create your invite. Please check your connection and try again."
                    showError = true
                }
                error.report(context: ["action": "send_buddy_invite", "source": "home_sheet"])
            }
        }
    }

    private func joinBuddy() {
        guard canJoin else { return }
        isJoining = true
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let relationship = try await container.supabaseDataService.acceptBuddyInvite(code: code)
                await MainActor.run {
                    isJoining = false
                    if let name = relationship.inviter?.displayName {
                        joinMessage = "You and \(name) are wellness buddies. You can see each other's streaks and send encouragement."
                    } else {
                        joinMessage = "You're connected with your wellness buddy. You can see each other's streaks and send encouragement."
                    }
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = "That code didn't work. It may have expired or already been used."
                    showError = true
                }
            }
        }
    }
}

// MARK: - Invite message

/// The words and link a buddy invite carries; the code is the one stored on the invite.
enum BuddyInviteMessage {
    static let subject = "Be my wellness buddy on MindFriend?"

    static func link(code: String) -> URL {
        URL(string: "https://getmindfriend.app/buddy/\(code)")!
    }

    static func body(code: String) -> String {
        "I'd love for us to be wellness buddies on MindFriend. Tap to join me: \(link(code: code).absoluteString)\n\nOr enter my code \(code) in MindFriend under Buddy."
    }
}

enum BuddyInviteOutcome: Identifiable {
    case sent(String)
    case notSent(String)

    var id: String {
        switch self {
        case .sent(let code): return "sent-\(code)"
        case .notSent(let code): return "not-sent-\(code)"
        }
    }
}

/// Messages for a text invite, Mail for an email invite, and the share sheet when this phone
/// can't send that kind of message.
enum BuddyInviteComposer: Identifiable {
    case message(recipient: String, code: String)
    case mail(recipient: String, code: String)
    case share(String)

    var id: String {
        switch self {
        case .message(_, let code): return "message-\(code)"
        case .mail(_, let code): return "mail-\(code)"
        case .share(let text): return "share-\(text.hashValue)"
        }
    }

    static func make(method: BuddyRelationship.InviteMethod, contact: String, code: String) -> BuddyInviteComposer {
        switch method {
        case .sms where MFMessageComposeViewController.canSendText():
            return .message(recipient: contact, code: code)
        case .email where MFMailComposeViewController.canSendMail():
            return .mail(recipient: contact, code: code)
        default:
            return .share(BuddyInviteMessage.body(code: code))
        }
    }

    private var code: String? {
        switch self {
        case .message(_, let code), .mail(_, let code): return code
        case .share(let text):
            return text.components(separatedBy: "/buddy/").last?.components(separatedBy: CharacterSet.alphanumerics.inverted).first
        }
    }

    @MainActor @ViewBuilder
    func view(onFinish: @escaping (BuddyInviteOutcome) -> Void) -> some View {
        let code = self.code ?? ""
        switch self {
        case .message(let recipient, let code):
            MessageComposerView(recipients: [recipient], body: BuddyInviteMessage.body(code: code)) { sent in
                onFinish(sent ? .sent(code) : .notSent(code))
            }
        case .mail(let recipient, let code):
            MailComposerView(recipients: [recipient], subject: BuddyInviteMessage.subject,
                             body: BuddyInviteMessage.body(code: code)) { sent in
                onFinish(sent ? .sent(code) : .notSent(code))
            }
        case .share(let text):
            InviteShareView(text: text) { completed in
                onFinish(completed ? .sent(code) : .notSent(code))
            }
        }
    }
}

private struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}

private struct MailComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
        }
    }
}

private struct InviteShareView: UIViewControllerRepresentable {
    let text: String
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            // Copying the text is not sending it.
            onFinish(completed && activity != .copyToPasteboard)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
