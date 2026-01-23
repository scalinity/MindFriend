//
//  DistortionPromptOverlay.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Non-intrusive overlay for cognitive distortion prompts
//

import SwiftUI

/// Non-intrusive overlay for cognitive distortion prompts
/// Displays during voice journaling with gentle language and reframing questions
struct DistortionPromptOverlay: View {

    // MARK: - Properties

    let prompt: DistortionPrompt
    let onDismiss: () -> Void
    let onExplore: () -> Void

    @State private var showDetails = false
    @State private var offsetY: CGFloat = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thought Pattern Noticed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text(prompt.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            onDismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                // Trigger phrase
                if !prompt.triggerPhrase.isEmpty {
                    Text("\"\(prompt.triggerPhrase)\"")
                        .font(.callout)
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.1))
                        )
                }

                // Reframing prompt
                Text(prompt.displayMessage)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(showDetails ? nil : 2)

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            onDismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.forward")
                            Text("Skip")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            onExplore()
                        }
                    } label: {
                        HStack {
                            Text("Explore This")
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                }

                // Show more details toggle
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        Text(showDetails ? "Show less" : "Learn more about this pattern")
                            .font(.caption)
                            .foregroundColor(.purple)

                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }

                if showDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is this?")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text(prompt.distortionEvent.distortionType.explanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .offset(y: offsetY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offsetY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            withAnimation(.spring(response: 0.3)) {
                                onDismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                offsetY = 0
                            }
                        }
                    }
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Preview

#if DEBUG
struct DistortionPromptOverlay_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEvent = DistortionEvent(
            userId: UUID(),
            sessionId: "preview-session",
            distortionType: .allOrNothing,
            transcriptText: "I always fail at everything. This is typical.",
            confidence: 0.85,
            detectionMethod: .pattern,
            userAcknowledged: false,
            createdAt: Date()
        )

        let samplePrompt = DistortionPrompt(
            distortionEvent: sampleEvent,
            shownAt: Date(),
            dismissed: false,
            acknowledged: false
        )

        ZStack {
            Color.gray.opacity(0.2)
                .ignoresSafeArea()

            DistortionPromptOverlay(
                prompt: samplePrompt,
                onDismiss: { print("Dismissed") },
                onExplore: { print("Explore") }
            )
        }
        .previewDisplayName("Distortion Prompt Overlay")
    }
}
#endif
