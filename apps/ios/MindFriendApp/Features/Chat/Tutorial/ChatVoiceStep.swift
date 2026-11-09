//
//  ChatVoiceStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Voice mode feature
//

import SwiftUI

/// Step 2: Explain voice chat capabilities
struct ChatVoiceStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var isPulsing = false
    @State private var showFeatures = false

    var body: some View {
        TutorialStepView(
            icon: "waveform.circle.fill",
            iconColor: SupportTheme.accent,
            headline: "Voice Mode",
            subheadline: "Sometimes typing isn't enough. Talk naturally and hear responses spoken back.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Voice visualization
                ZStack {
                    // Animated rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(SupportTheme.accent.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: CGFloat(60 + i * 30), height: CGFloat(60 + i * 30))
                            .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.1 : 1.0))
                            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: isPulsing
                            )
                    }

                    // Microphone icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(SupportTheme.accent)
                }

                // Voice features
                VStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(Array(voiceFeatures.enumerated()), id: \.element.text) { index, feature in
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: feature.icon)
                                .font(.body)
                                .foregroundStyle(feature.color)
                                .frame(minWidth: 24)

                            Text(feature.text)
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .opacity(showFeatures ? 1 : 0)
                        .offset(x: reduceMotion ? 0 : (showFeatures ? 0 : -10))
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.5 + Double(index) * 0.15),
                            value: showFeatures
                        )
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Premium note
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                    Text("Premium feature")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .onAppear {
                isPulsing = true
                showFeatures = true
            }
        }
    }

    private var voiceFeatures: [(icon: String, color: Color, text: String)] {
        [
            ("mic.fill", SupportTheme.accent, "Speak naturally, no typing needed"),
            ("speaker.wave.2.fill", SupportTheme.accent, "Hear warm, natural responses"),
            ("figure.walk", SupportTheme.accent, "Chat hands-free while walking")
        ]
    }
}

#Preview {
    ChatVoiceStep(onNext: {}, onSkip: {})
}
