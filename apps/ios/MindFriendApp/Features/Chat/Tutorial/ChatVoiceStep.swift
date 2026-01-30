//
//  ChatVoiceStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Voice mode feature
//

import SwiftUI

/// Step 2: Explain voice chat capabilities
struct ChatVoiceStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var isPulsing = false
    @State private var showFeatures = false

    var body: some View {
        TutorialStepView(
            icon: "waveform.circle.fill",
            iconColor: .purple,
            headline: "Voice Mode",
            subheadline: "Sometimes typing isn't enough. Talk naturally and hear responses spoken back.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Voice visualization
                ZStack {
                    // Animated rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.purple.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: CGFloat(60 + i * 30), height: CGFloat(60 + i * 30))
                            .scaleEffect(isPulsing ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: isPulsing
                            )
                    }

                    // Microphone icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.purple)
                }

                // Voice features
                VStack(spacing: 8) {
                    ForEach(Array(voiceFeatures.enumerated()), id: \.element.text) { index, feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.body)
                                .foregroundStyle(feature.color)
                                .frame(width: 24)

                            Text(feature.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .opacity(showFeatures ? 1 : 0)
                        .offset(x: showFeatures ? 0 : -10)
                        .animation(
                            .easeOut(duration: 0.3).delay(0.5 + Double(index) * 0.15),
                            value: showFeatures
                        )
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                // Premium note
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Premium feature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            ("mic.fill", .purple, "Speak naturally, no typing needed"),
            ("speaker.wave.2.fill", .blue, "Hear warm, natural responses"),
            ("figure.walk", .green, "Chat hands-free while walking")
        ]
    }
}

#Preview {
    ChatVoiceStep(onNext: {}, onSkip: {})
}
