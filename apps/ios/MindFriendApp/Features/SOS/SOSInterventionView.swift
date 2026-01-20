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
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.3),
                    Color(red: 0.05, green: 0.08, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Phase-based content
            phaseContent
        }
        .onChange(of: container.sosCoordinator.phase) { _, newPhase in
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
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Starting calming session...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
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

        case .breathing(let cycleIndex, let totalCycles, _):
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
    let remaining: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Main countdown circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 3.0)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    Text("\(remaining)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: remaining)

                    Text("seconds")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Message
            VStack(spacing: 12) {
                Text("Taking a moment")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Your emergency contact will be notified\nunless you cancel.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Countdown: \(remaining) seconds. Your emergency contact will be notified unless you cancel.")
    }
}

// MARK: - Error View

private struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Crisis resources reminder
            VStack(spacing: 8) {
                Text("If you need immediate support:")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 20) {
                    Button {
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Call 988", systemImage: "phone.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    Button {
                        if let url = URL(string: "sms:741741?body=HOME") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Text 741741", systemImage: "message.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.8))
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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    SOSInterventionView()
        .environmentObject(DependencyContainer.preview)
        .environmentObject(AppState())
}
