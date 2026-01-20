import SwiftUI

// MARK: - Onboarding Container

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var currentStep: OnboardingStep = .quiz
    @State private var selectedFocus: WellnessFocus?
    @State private var isCompleting = false
    @State private var showError = false
    @State private var errorMessage = ""

    enum OnboardingStep: Int, CaseIterable {
        case quiz = 0
        case aiGreeting = 1
        case buddyInvite = 2
        case complete = 3

        var progress: Double {
            Double(self.rawValue + 1) / Double(OnboardingStep.allCases.count)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal)
                .padding(.top)

            // Step content
            Group {
                switch currentStep {
                case .quiz:
                    OnboardingQuizView(
                        selectedFocus: $selectedFocus,
                        onContinue: advanceToAIGreeting,
                        onSkip: { completeOnboarding(focus: .general, skippedQuiz: true) }
                    )

                case .aiGreeting:
                    OnboardingAIGreetingView(
                        wellnessFocus: selectedFocus ?? .general,
                        onComplete: advanceToBuddyInvite
                    )

                case .buddyInvite:
                    OnboardingBuddyInviteView(
                        onContinue: { completeOnboarding(focus: selectedFocus ?? .general, skippedQuiz: false) },
                        onSkip: { completeOnboarding(focus: selectedFocus ?? .general, skippedQuiz: false) }
                    )

                case .complete:
                    OnboardingCompleteView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .alert("Setup Error", isPresented: $showError) {
            Button("Try Again") {
                currentStep = .quiz
                isCompleting = false
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Analytics.shared.track(.onboardingStarted)
        }
    }

    private func advanceToAIGreeting() {
        withAnimation {
            currentStep = .aiGreeting
        }
    }

    private func advanceToBuddyInvite() {
        withAnimation {
            currentStep = .buddyInvite
        }
        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "ai_greeting"
        ])
    }

    private func completeOnboarding(focus: WellnessFocus, skippedQuiz: Bool) {
        guard !isCompleting else { return }
        isCompleting = true

        withAnimation {
            currentStep = .complete
        }

        Task {
            do {
                // Atomic update: save wellness focus + mark onboarding complete
                try await container.supabaseDataService.completeOnboarding(focus: focus)

                // Track skip event if applicable
                if skippedQuiz {
                    Analytics.shared.track(.onboardingSkipped)
                }

                // Fetch fresh profile with updated fields
                let profile = try await container.supabaseAuthService.fetchProfile()

                // Set crash reporter context
                CrashReporter.shared.setUser(
                    id: profile.id,
                    email: profile.email,
                    username: profile.handle
                )
                Analytics.shared.identify(userId: profile.id)
                Analytics.shared.setUserProperty(.subscriptionTier, value: profile.entitlements.tier.rawValue)
                Analytics.shared.track(.onboardingCompleted, properties: [
                    "wellness_focus": focus.rawValue,
                    "skipped_quiz": skippedQuiz
                ])

                // Update app state to transition to main app
                await MainActor.run {
                    appState.completeOnboarding(user: profile)
                }
            } catch {
                await MainActor.run {
                    isCompleting = false
                    errorMessage = "Unable to complete setup. Please check your connection and try again."
                    showError = true
                }
                error.report(context: ["action": "complete_onboarding"])
            }
        }
    }
}

// MARK: - Quiz View

struct OnboardingQuizView: View {
    @Binding var selectedFocus: WellnessFocus?
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Text("What brings you here today?")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("This helps me personalize your experience")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)

                // Options
                VStack(spacing: 12) {
                    ForEach(WellnessFocus.selectableOptions, id: \.self) { focus in
                        WellnessFocusButton(
                            focus: focus,
                            isSelected: selectedFocus == focus,
                            action: { selectedFocus = focus }
                        )
                    }
                }
                .padding(.horizontal, 24)

                // Testimonials - social proof
                TestimonialsCarousel()
                    .padding(.top, 8)

                // Privacy banner - trust building
                PrivacyBanner()
                    .padding(.horizontal, 24)

                // Actions
                VStack(spacing: 12) {
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedFocus != nil ? Color.accentColor : Color.secondary.opacity(0.3))
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(selectedFocus == nil)
                    .accessibilityLabel("Continue")
                    .accessibilityHint(selectedFocus != nil ? "Proceed to AI greeting" : "Select a focus area first")

                    Button("Skip for now", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip personalization")
                        .accessibilityHint("Skip the quiz and use default settings")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Wellness Focus Button

struct WellnessFocusButton: View {
    let focus: WellnessFocus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(focus.emoji)
                    .font(.title2)

                Text(focus.displayTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(focus.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - AI Greeting View

struct OnboardingAIGreetingView: View {
    let wellnessFocus: WellnessFocus
    let onComplete: () -> Void

    @State private var messages: [OnboardingMessage] = []
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var userMessageCount = 0
    @FocusState private var isInputFocused: Bool

    private let maxExchanges = 2

    var body: some View {
        VStack(spacing: 0) {
            // Chat area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            OnboardingMessageBubble(message: message)
                                .id(message.id)
                        }

                        if isTyping {
                            OnboardingTypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnSwipe()
                .onTapGesture {
                    hideKeyboard()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        if isTyping {
                            proxy.scrollTo("typing", anchor: .bottom)
                        } else {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isTyping) { _, newValue in
                    if newValue {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                        .accessibilityLabel("Message input")
                        .accessibilityHint("Type your response to the AI assistant")

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send message")
                    .accessibilityHint(canSend ? "Send your message" : "Type a message first")
                }

                // Show "Get Started" after exchanges or as skip option
                if userMessageCount >= maxExchanges {
                    Button(action: onComplete) {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .accessibilityLabel("Get started")
                    .accessibilityHint("Complete onboarding and enter the app")
                } else if !messages.isEmpty {
                    Button("Skip to app", action: onComplete)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip to app")
                        .accessibilityHint("Skip the conversation and enter the app")
                }
            }
            .padding()
        }
        .task {
            // AI sends first message after a short delay
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isTyping = true

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            isTyping = false
            messages.append(OnboardingMessage(
                role: .assistant,
                content: wellnessFocus.aiGreeting
            ))
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTyping
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isTyping else { return }

        // Add user message
        messages.append(OnboardingMessage(role: .user, content: content))
        inputText = ""
        userMessageCount += 1

        // Show typing indicator
        isTyping = true

        // Generate canned response after delay using Task for proper lifecycle management
        let response = generateResponse()
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            isTyping = false
            messages.append(OnboardingMessage(
                role: .assistant,
                content: response
            ))
        }

        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "ai_greeting",
            "message_count": userMessageCount
        ])
    }

    private func generateResponse() -> String {
        if userMessageCount == 1 {
            return "Thank you for sharing that with me. I'm here for you, and together we'll work on building habits that help. Ready to explore the app?"
        } else {
            return "I'm glad we connected! The app has daily quests, mood tracking, and more to support your journey. Let's get started!"
        }
    }
}

// MARK: - Onboarding Message Model

struct OnboardingMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
}

// MARK: - Message Bubble

struct OnboardingMessageBubble: View {
    let message: OnboardingMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .cornerRadius(20)
                .accessibilityLabel(isUser ? "You said: \(message.content)" : "MindFriend said: \(message.content)")

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct OnboardingTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(20)
            .accessibilityLabel("MindFriend is typing")

            Spacer()
        }
        .onAppear { animating = true }
    }
}

// MARK: - Buddy Invite View

struct OnboardingBuddyInviteView: View {
    @EnvironmentObject var container: DependencyContainer

    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var contactMethod: BuddyRelationship.InviteMethod = .sms
    @State private var contact = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var inviteCode: String?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // Icon
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                // Header
                VStack(spacing: 12) {
                    Text("Invite a Wellness Buddy")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("People with an accountability partner are **3x more likely** to reach their wellness goals!")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

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

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    BuddyBenefitRow(icon: "flame.fill", text: "See each other's streaks")
                    BuddyBenefitRow(icon: "hand.thumbsup.fill", text: "Send encouragement")
                    BuddyBenefitRow(icon: "gift.fill", text: "Both earn bonus XP")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                Spacer(minLength: 24)

                // Actions
                VStack(spacing: 12) {
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
                    .accessibilityLabel("Send invite")
                    .accessibilityHint(canSend ? "Send an invite to your buddy" : "Enter a valid contact first")

                    Button("Skip for now", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip buddy invite")
                        .accessibilityHint("Continue without inviting a buddy")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .dismissKeyboardOnSwipe()
        .onTapGesture {
            hideKeyboard()
        }
        .alert("Invite Sent!", isPresented: $showSuccess) {
            Button("Continue", action: onContinue)
        } message: {
            if let code = inviteCode {
                Text("Your buddy will receive an invitation. Share this code if needed: **\(code)**")
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
                    "source": "onboarding"
                ])
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Could not send invite. Please check the contact and try again."
                    showError = true
                }
                error.report(context: ["action": "send_buddy_invite", "source": "onboarding"])
            }
        }
    }
}

// MARK: - Buddy Benefit Row

struct BuddyBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Complete View

struct OnboardingCompleteView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Loading")

            Text("Setting up your experience...")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setting up your experience, please wait")
    }
}

// MARK: - Preview

#Preview("Quiz") {
    OnboardingFlow()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
