//  ContextualMicroMomentView.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  Wrapper view for displaying context-triggered micro-moments

import SwiftUI

/// View for displaying a context-triggered micro-moment with explanation
struct ContextualMicroMomentView: View {
    let template: MicroMomentTemplate
    let contextMessage: String?
    let deliveryId: UUID?
    let onStart: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var dependencies: DependencyContainer
    @State private var showPlayer = false
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Context message (if provided)
            if let contextMessage = contextMessage {
                contextSection(message: contextMessage)
            }

            // Intervention preview
            templatePreview

            // Action buttons
            buttonSection
        }
        .padding(SupportTheme.Spacing.l)
        .background(SupportTheme.canvas)
        .cornerRadius(SupportTheme.cardRadius)
        .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, SupportTheme.Spacing.m)
        .fullScreenCover(isPresented: $showPlayer) {
            MicroMomentPlayerView(template: template) { completionData in
                handleCompletion(completionData)
                showPlayer = false
            }
        }
    }

    private func contextSection(message: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(SupportTheme.accent)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var templatePreview: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(SupportTheme.accent.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: template.type.icon)
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
            }

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text(template.title)
                    .font(.title3.weight(.semibold))

                if let description = template.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: SupportTheme.Spacing.m) {
                    Label(template.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if let energyEffect = template.energyEffect {
                        Label(energyEffect.displayName, systemImage: energyIcon(for: energyEffect))
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var buttonSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Start button
            Button {
                hasStarted = true
                onStart()
                showPlayer = true
            } label: {
                Text("Start Exercise")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.m)
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .cornerRadius(SupportTheme.controlRadius)
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Text("Not right now")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    private func energyIcon(for effect: EnergyEffect) -> String {
        switch effect {
        case .calming:
            return "moon.stars"
        case .energizing:
            return "bolt"
        case .neutral:
            return "circle"
        }
    }

    private func handleCompletion(_ completionData: MicroCompletionData) {
        // Track completion and rating
        guard let deliveryId = deliveryId else { return }

        Task {
            do {
                try await dependencies.interventionService.updateDelivery(
                    deliveryId: deliveryId,
                    completed: true,
                    rating: completionData.feltHelpful == true ? 5 : (completionData.feltHelpful == false ? 2 : nil),
                    feedback: nil
                )
            } catch {
                print("Error updating delivery: \(error)")
            }
        }
    }
}

// MARK: - Sheet Wrapper

struct ContextualMicroMomentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: MicroMomentTemplate
    let contextMessage: String?
    let deliveryId: UUID?
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.canvas.opacity(0.4)
                .ignoresSafeArea()

            ContextualMicroMomentView(
                template: template,
                contextMessage: contextMessage,
                deliveryId: deliveryId,
                onStart: {
                    onStart()
                },
                onDismiss: {
                    onDismiss()
                    dismiss()
                }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ContextualMicroMomentView(
        template: MicroMomentTemplate(
            id: "preview-id",
            name: "Calm Breath",
            slug: "calm-breath",
            type: .breathing,
            title: "Take a Calm Breath",
            description: "4-6 breathing pattern to activate calm response",
            durationSeconds: 45,
            instructions: [],
            animationType: .breathingCircle,
            audioUrl: nil,
            hapticPattern: nil,
            suggestedContexts: ["stress"],
            energyEffect: .calming,
            isPremium: false,
            isActive: true,
            sortOrder: 0,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ),
        contextMessage: "I noticed your heart rate is elevated. A quick breathing exercise might help.",
        deliveryId: UUID(),
        onStart: { print("Started") },
        onDismiss: { print("Dismissed") }
    )
    .environmentObject(DependencyContainer.preview)
}
