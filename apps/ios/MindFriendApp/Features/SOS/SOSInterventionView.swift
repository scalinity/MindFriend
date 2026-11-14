// SOSInterventionView.swift
// MindFriend - Main SOS Intervention Container

import SwiftUI

/// Main container view for the SOS intervention flow
/// Routes between different phases of the intervention
struct SOSInterventionView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Directly observe the coordinator for proper SwiftUI updates
    private var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    // Track phase locally to ensure view updates
    @State private var currentPhase: SOSPhase = .ready

    var body: some View {
        ZStack {
            // Background gradient
            SupportTheme.surface
                .ignoresSafeArea()

            // Phase-based content
            phaseContent
        }
        .onReceive(container.sosCoordinator.$phase) { newPhase in
            currentPhase = newPhase
            handlePhaseChange(newPhase)
        }
        .onAppear {
            // Reset coordinator and start fresh SOS session
            sosCoordinator.reset()
            currentPhase = .ready
            Task {
                // Load settings first (required for breathing patterns and preferences)
                await sosCoordinator.loadSettings()
                await sosCoordinator.startSOS(from: "intervention_view")
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch currentPhase {
        case .ready:
            // Starting state - show brief loading
            VStack(spacing: SupportTheme.Spacing.l) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(SupportTheme.textPrimary)

                Text("Starting calming session...")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
            }

        case .countdown(let remaining):
            CountdownView(
                remaining: remaining,
                onCancel: {
                    Task {
                        await sosCoordinator.cancelSOS()
                    }
                    dismiss()
                }
            )

        case .breathing(_, _, _):
            SOSBreathingView(
                onComplete: {
                    sosCoordinator.completeBreathing()
                },
                onSkip: {
                    sosCoordinator.skipToResources()
                }
            )

        case .grounding(let sense):
            SOSGroundingView(
                currentSense: sense,
                onComplete: {
                    sosCoordinator.completeGrounding()
                },
                onSkip: {
                    sosCoordinator.skipToResources()
                }
            )

        case .resources:
            SOSResourcesView(
                onContinue: {
                    sosCoordinator.proceedToCheckIn()
                },
                onChatWithAI: {
                    // Navigate to chat tab and open new chat
                    appState.shouldOpenNewChat = true
                    appState.selectedTab = .chat
                    sosCoordinator.exitToChat()
                    dismiss()
                }
            )

        case .checkIn:
            SOSCheckInView { helpfulnessRating, moodAfter in
                Task {
                    await sosCoordinator.completeCheckIn(
                        helpfulnessRating: helpfulnessRating,
                        moodAfter: moodAfter
                    )
                }
                dismiss()
            }

        case .complete:
            // Automatically dismiss when complete
            Color.clear
                .onAppear {
                    dismiss()
                }

        case .cancelled:
            // Automatically dismiss when cancelled
            Color.clear
                .onAppear {
                    dismiss()
                }

        case .error(let message):
            ErrorView(message: message) {
                Task {
                    await sosCoordinator.cancelSOS()
                }
                dismiss()
            }
        }
    }

    private func handlePhaseChange(_ phase: SOSPhase) {
        // Trigger haptic for phase transitions
        switch phase {
        case .breathing:
            sosCoordinator.triggerHaptic(.phaseStart)
        case .grounding:
            sosCoordinator.triggerHaptic(.phaseStart)
        case .resources:
            sosCoordinator.triggerHaptic(.gentleEnd)
        case .checkIn:
            sosCoordinator.triggerHaptic(.gentleEnd)
        case .complete:
            sosCoordinator.triggerHaptic(.success)
        default:
            break
        }
    }
}

// MARK: - Countdown View

private struct CountdownView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let remaining: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xl) {
            Spacer()

            // Main countdown circle
            ZStack {
                Circle()
                    .stroke(SupportTheme.textPrimary.opacity(0.2), lineWidth: 8)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 3.0)
                    .stroke(
                        SupportTheme.surface,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("\(remaining)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(SupportTheme.textPrimary)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut), value: remaining)

                    Text("seconds")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                }
            }

            // Message
            VStack(spacing: SupportTheme.Spacing.s) {
                Text("Taking a moment")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.semibold)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("Your emergency contact will be notified\nunless you cancel.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.m)
                    .background(SupportTheme.textPrimary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.xl)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Countdown: \(remaining) seconds. Your emergency contact will be notified unless you cancel.")
    }
}

// MARK: - Error View

private struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.Status.caution)

            Text("Something went wrong")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)
                .foregroundStyle(SupportTheme.textPrimary)

            Text(message)
                .font(.body)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()

            // Crisis resources reminder
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("If you need immediate support:")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))

                HStack(spacing: SupportTheme.Spacing.l) {
                    Button {
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Call 988", systemImage: "phone.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SupportTheme.textPrimary)
                            .padding(.horizontal, SupportTheme.Spacing.m)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(SupportTheme.surface)
                            .clipShape(Capsule())
                    }

                    Button {
                        if let url = URL(string: "sms:741741?body=HOME") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Text 741741", systemImage: "message.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SupportTheme.textPrimary)
                            .padding(.horizontal, SupportTheme.Spacing.m)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(SupportTheme.surface)
                            .clipShape(Capsule())
                    }
                }
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Text("Close")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.m)
                    .background(SupportTheme.textPrimary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.xl)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }
}

#Preview {
    SOSInterventionView()
        .environmentObject(DependencyContainer.preview)
        .environmentObject(AppState())
}
