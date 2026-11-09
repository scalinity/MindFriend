// SOSResourcesView.swift
// MindFriend - Crisis Resources for SOS Intervention

import SwiftUI

/// Crisis resources and support options screen
struct SOSResourcesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    let onContinue: () -> Void
    let onChatWithAI: () -> Void

    @State private var selectedMood: Int = 3

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(SupportTheme.accent)

                    Text("How are you feeling now?")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)
                        .foregroundStyle(SupportTheme.textPrimary)
                }
                .padding(.top, SupportTheme.Spacing.xl)

                // Mood selector
                HStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            selectedMood = mood
                            sosCoordinator.triggerHaptic(.groundingTap)
                        } label: {
                            Text(moodEmoji(for: mood))
                                .font(.system(size: 36))
                                .scaleEffect(reduceMotion ? 1 : (selectedMood == mood ? 1.2 : 1.0))
                                .opacity(selectedMood == mood ? 1.0 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(moodLabel(for: mood))
                        .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.xs)

                Divider()
                    .background(SupportTheme.textPrimary.opacity(0.3))
                    .padding(.horizontal, SupportTheme.Spacing.xl)

                // Resources section
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text("What would help?")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))

                    VStack(spacing: SupportTheme.Spacing.s) {
                        // Chat with MindFriend
                        ResourceButton(
                            icon: "bubble.left.fill",
                            title: "Chat with MindFriend",
                            subtitle: "Talk through what you're feeling",
                            color: SupportTheme.accent
                        ) {
                            onChatWithAI()
                        }

                        // Call 988
                        ResourceButton(
                            icon: "phone.fill",
                            title: "Call 988",
                            subtitle: "Suicide & Crisis Lifeline (24/7)",
                            color: SupportTheme.accent
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
                            color: SupportTheme.accent
                        ) {
                            if let url = URL(string: "sms:741741?body=HOME") {
                                UIApplication.shared.open(url)
                            }
                        }

                        // Emergency Contact
                        if let settings = sosCoordinator.settings,
                            let contactName = settings.emergencyContactName,
                            let contactPhone = settings.emergencyContactPhone
                        {
                            ResourceButton(
                                icon: "person.fill",
                                title: "Contact \(contactName)",
                                subtitle: "Send them a message",
                                color: SupportTheme.accent
                            ) {
                                let message =
                                    "I'm having a hard time right now. Just wanted to let you know I'm using my MindFriend app to help."
                                if let encodedMessage = message.addingPercentEncoding(
                                    withAllowedCharacters: .urlQueryAllowed),
                                    let url = URL(string: "sms:\(contactPhone)?body=\(encodedMessage)")
                                {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.l)
                }

                Spacer(minLength: 40)

                // Continue button
                Button {
                    sosCoordinator.recordMoodBefore(selectedMood)
                    onContinue()
                } label: {
                    Text("I'm feeling better")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SupportTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.m)
                        .background(
                            SupportTheme.surface
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SupportTheme.surface
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
            HStack(spacing: SupportTheme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.4))
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.textPrimary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
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
