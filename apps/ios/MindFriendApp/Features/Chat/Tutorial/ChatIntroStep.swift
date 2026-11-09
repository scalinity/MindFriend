//
//  ChatIntroStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Meet your AI companion
//

import SwiftUI

/// Step 1: Introduce the AI companion
struct ChatIntroStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            iconColor: SupportTheme.accent,
            headline: "Meet Your AI Companion",
            subheadline: "A supportive friend who's always here to listen, without judgment.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Chat preview
                ForEach(0..<messages.count, id: \.self) { index in
                    if index <= currentMessage {
                        ChatBubble(
                            text: messages[index].text,
                            isUser: messages[index].isUser
                        )
                        .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .asymmetric(
                            insertion: .move(edge: messages[index].isUser ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }

                Spacer().frame(height: 8)

                // Feature badges
                HStack(spacing: SupportTheme.Spacing.s) {
                    FeatureBadge(icon: "lock.shield.fill", text: "Private")
                    FeatureBadge(icon: "clock.fill", text: "24/7")
                    FeatureBadge(icon: "heart.fill", text: "Supportive")
                }
                .opacity(currentMessage >= 2 ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .onAppear {
                animateMessages()
            }
        }
    }

    private func animateMessages() {
        showMessages = true
        for i in 1..<messages.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
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
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.vertical, SupportTheme.Spacing.s)
                .background(isUser ? SupportTheme.accent : SupportTheme.surface)
                .foregroundStyle(isUser ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Feature Badge

private struct FeatureBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fixedSize()
        }
        .foregroundStyle(SupportTheme.textSecondary)
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.surface)
        .clipShape(Capsule())
    }
}

#Preview {
    ChatIntroStep(onNext: {}, onSkip: {})
}
