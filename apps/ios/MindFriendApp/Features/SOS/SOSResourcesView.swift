// SOSResourcesView.swift
// MindFriend - Crisis Resources for SOS Intervention

import SwiftUI

/// Crisis resources and support options screen
struct SOSResourcesView: View {
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let onContinue: () -> Void
    let onChatWithAI: () -> Void

    @State private var selectedMood: Int = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)

                    Text("How are you feeling now?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)

                // Mood selector
                HStack(spacing: 16) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            selectedMood = mood
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Text(moodEmoji(for: mood))
                                .font(.system(size: 36))
                                .scaleEffect(selectedMood == mood ? 1.2 : 1.0)
                                .opacity(selectedMood == mood ? 1.0 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(moodLabel(for: mood))
                        .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 40)

                // Resources section
                VStack(spacing: 12) {
                    Text("What would help?")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))

                    VStack(spacing: 12) {
                        // Chat with MindFriend
                        ResourceButton(
                            icon: "bubble.left.fill",
                            title: "Chat with MindFriend",
                            subtitle: "Talk through what you're feeling",
                            color: .blue
                        ) {
                            onChatWithAI()
                        }

                        // Call 988
                        ResourceButton(
                            icon: "phone.fill",
                            title: "Call 988",
                            subtitle: "Suicide & Crisis Lifeline (24/7)",
                            color: .green
                        ) {
                            if let url = URL(string: "tel://988") {
                                UIApplication.shared.open(url)
                            }
                        }

                        // Text Crisis Line
                        ResourceButton(
                            icon: "message.fill",
                            title: "Text HOME to 741741",
                            subtitle: "Crisis Text Line (24/7)",
                            color: .purple
                        ) {
                            if let url = URL(string: "sms:741741?body=HOME") {
                                UIApplication.shared.open(url)
                            }
                        }

                        // Emergency Contact
                        if let settings = sosCoordinator.settings,
                           let contactName = settings.emergencyContactName,
                           let contactPhone = settings.emergencyContactPhone {
                            ResourceButton(
                                icon: "person.fill",
                                title: "Contact \(contactName)",
                                subtitle: "Send them a message",
                                color: .orange
                            ) {
                                let message = "I'm having a hard time right now. Just wanted to let you know I'm using my MindFriend app to help."
                                if let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                   let url = URL(string: "sms:\(contactPhone)?body=\(encodedMessage)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 40)

                // Continue button
                Button {
                    sosCoordinator.recordMoodBefore(selectedMood)
                    onContinue()
                } label: {
                    Text("I'm feeling better")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.teal, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.2, blue: 0.35),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func moodEmoji(for mood: Int) -> String {
        switch mood {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😌"
        default: return "😐"
        }
    }

    private func moodLabel(for mood: Int) -> String {
        switch mood {
        case 1: return "Very upset"
        case 2: return "Somewhat upset"
        case 3: return "Neutral"
        case 4: return "Somewhat calm"
        case 5: return "Calm"
        default: return "Neutral"
        }
    }
}

// MARK: - Resource Button

struct ResourceButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SOSResourcesView(
        onContinue: {},
        onChatWithAI: {}
    )
    .environmentObject(DependencyContainer.preview)
}
