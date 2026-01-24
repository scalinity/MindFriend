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
        VStack(spacing: 24) {
            // Context message (if provided)
            if let contextMessage = contextMessage {
                contextSection(message: contextMessage)
            }

            // Intervention preview
            templatePreview

            // Action buttons
            buttonSection
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 20)
        .fullScreenCover(isPresented: $showPlayer) {
            MicroMomentPlayerView(template: template) { completionData in
                handleCompletion(completionData)
                showPlayer = false
            }
        }
    }

    private func contextSection(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.blue)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var templatePreview: some View {
        VStack(spacing: 12) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(template.type.color.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: template.type.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(template.type.color)
            }

            VStack(spacing: 4) {
                Text(template.title)
                    .font(.title3.weight(.semibold))

                if let description = template.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 16) {
                    Label(template.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let energyEffect = template.energyEffect {
                        Label(energyEffect.displayName, systemImage: energyIcon(for: energyEffect))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var buttonSection: some View {
        VStack(spacing: 12) {
            // Start button
            Button {
                hasStarted = true
                onStart()
                showPlayer = true
            } label: {
                Text("Start Exercise")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Text("Not right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            Color.black.opacity(0.4)
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
