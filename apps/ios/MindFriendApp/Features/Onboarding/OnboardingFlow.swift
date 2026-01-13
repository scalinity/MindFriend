import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0

    var body: some View {
        VStack {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Content
            TabView(selection: $currentStep) {
                WelcomeStep(onNext: { currentStep = 1 })
                    .tag(0)

                PrivacyStep(onNext: { currentStep = 2 })
                    .tag(1)

                NotificationStep(onNext: { currentStep = 3 })
                    .tag(2)

                PersonalizationStep(onComplete: completeOnboarding)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 16) {
                Text("Welcome to MindFriend")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your personal AI wellness companion. Let's set up a few things to personalize your experience.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

struct PrivacyStep: View {
    let onNext: () -> Void
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 16) {
                Text("Your Privacy Matters")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(icon: "checkmark.shield", text: "Your conversations are private and secure")
                    PrivacyPoint(icon: "heart.text.square", text: "Crisis resources available anytime")
                    PrivacyPoint(icon: "brain", text: "AI provides support, not medical advice")
                    PrivacyPoint(icon: "trash", text: "Delete your data anytime")
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 16) {
                Toggle(isOn: $accepted) {
                    Text("I understand and agree to the Terms of Service and Privacy Policy")
                        .font(.caption)
                }
                .toggleStyle(CheckboxToggleStyle())
                .padding(.horizontal, 24)

                Button(action: onNext) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accepted ? Color.accentColor : Color.secondary)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!accepted)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
    }
}

struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }
}

struct NotificationStep: View {
    let onNext: () -> Void
    @State private var requestingPermission = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 16) {
                Text("Stay on Track")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Get gentle reminders for your daily quest and wellness check-ins. You can customize or disable notifications anytime.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    requestNotificationPermission()
                } label: {
                    Text("Enable Notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                Button {
                    onNext()
                } label: {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func requestNotificationPermission() {
        requestingPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                requestingPermission = false
                onNext()
            }
        }
    }
}

struct PersonalizationStep: View {
    let onComplete: () -> Void
    @State private var selectedTone: AITone = .friendly
    @State private var questTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()

    var body: some View {
        VStack(spacing: 24) {
            Text("Personalize Your Experience")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)

            ScrollView {
                VStack(spacing: 32) {
                    // AI Tone
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How should I sound?")
                            .font(.headline)

                        ForEach(AITone.allCases, id: \.self) { tone in
                            Button {
                                selectedTone = tone
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tone.displayName)
                                            .fontWeight(.medium)
                                        Text(tone.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedTone == tone {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding()
                                .background(selectedTone == tone ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Quest time
                    VStack(alignment: .leading, spacing: 12) {
                        Text("When should I send your daily quest?")
                            .font(.headline)

                        DatePicker("Quest Time", selection: $questTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 24)
            }

            Button(action: onComplete) {
                Text("Let's Go!")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(AppState())
}
