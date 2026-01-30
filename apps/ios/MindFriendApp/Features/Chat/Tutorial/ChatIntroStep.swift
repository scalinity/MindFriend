//
//  ChatIntroStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Meet your AI companion
//

import SwiftUI

/// Step 1: Introduce the AI companion
struct ChatIntroStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMessages = false
    @State private var currentMessage = 0

    private let messages = [
        (isUser: false, text: "Hi there! I'm here to listen and support you."),
        (isUser: true, text: "I've been feeling a bit stressed lately..."),
        (isUser: false, text: "I hear you. Would you like to talk about what's been on your mind?")
    ]

    var body: some View {
        TutorialStepView(
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: .blue,
            headline: "Meet Your AI Companion",
            subheadline: "A supportive friend who's always here to listen, without judgment.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Chat preview
                ForEach(0..<messages.count, id: \.self) { index in
                    if index <= currentMessage {
                        ChatBubble(
                            text: messages[index].text,
                            isUser: messages[index].isUser
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: messages[index].isUser ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }

                Spacer().frame(height: 8)

                // Feature badges
                HStack(spacing: 12) {
                    FeatureBadge(icon: "lock.shield.fill", text: "Private")
                    FeatureBadge(icon: "clock.fill", text: "24/7")
                    FeatureBadge(icon: "heart.fill", text: "Supportive")
                }
                .opacity(currentMessage >= 2 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .onAppear {
                animateMessages()
            }
        }
    }

    private func animateMessages() {
        showMessages = true
        for i in 1..<messages.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                withAnimation(.easeOut(duration: 0.3)) {
                    currentMessage = i
                }
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Feature Badge

private struct FeatureBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fixedSize()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

#Preview {
    ChatIntroStep(onNext: {}, onSkip: {})
}
