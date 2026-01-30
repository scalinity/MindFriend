// MindFriend Program Certificate Celebration View
// Full celebration view for program completion with certificate

import SwiftUI

/// Full-screen celebration for program completion with certificate display
struct ProgramCertificateCelebrationView: View {
    let programName: String
    let certificateNumber: String
    let completionStats: CompletionStats
    let onDismiss: () -> Void
    let onShareToCircle: (() async -> Void)?
    let onShareExternally: (() -> Void)?

    @State private var showConfetti = false
    @State private var showCertificate = false
    @State private var showContent = false
    @State private var showStats = false
    @State private var showButtons = false
    @State private var isSharing = false
    @State private var hasSharedToCircle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goldColor = Color(red: 0.85, green: 0.65, blue: 0.13)

    struct CompletionStats {
        let daysCompleted: Int
        let longestStreak: Int
        let skipsUsed: Int
        let totalDays: Int
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.15), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Gold accent gradient at top
            LinearGradient(
                colors: [goldColor.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .opacity(showContent ? 1 : 0)

            // Confetti particles
            if showConfetti {
                CertificateConfettiParticles()
            }

            // Main content
            VStack(spacing: 20) {
                Spacer()

                // "PROGRAM COMPLETE!" title
                Text("PROGRAM COMPLETE!")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundStyle(goldColor)
                    .tracking(2)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                // Certificate
                if showCertificate {
                    CertificateUnfurlEffect(
                        programName: programName,
                        certificateNumber: certificateNumber,
                        completionDate: Date()
                    )
                    .frame(height: 280)
                }

                // Stats row
                HStack(spacing: 24) {
                    CelebrationStatBadge(
                        icon: "calendar.badge.checkmark",
                        value: "\(completionStats.daysCompleted)",
                        label: "Days"
                    )

                    CelebrationStatBadge(
                        icon: "flame.fill",
                        value: "\(completionStats.longestStreak)",
                        label: "Best Streak"
                    )

                    CelebrationStatBadge(
                        icon: "arrow.triangle.2.circlepath",
                        value: "\(completionStats.skipsUsed)",
                        label: "Skips Used"
                    )
                }
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 20)
                .padding(.top, 16)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Share to Circle
                    if onShareToCircle != nil {
                        Button {
                            Task { await shareToCircle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                Text(hasSharedToCircle ? "Shared to Circle" : "Share with Circle")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(hasSharedToCircle ? .green : goldColor)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                        }
                        .disabled(hasSharedToCircle || isSharing)
                    }

                    // Share externally
                    if onShareExternally != nil {
                        Button {
                            onShareExternally?()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Externally")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    // Continue button
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButtons ? 1 : 0)
                .offset(y: showButtons ? 0 : 30)
            }
        }
        .onAppear {
            if reduceMotion {
                showConfetti = true
                showCertificate = true
                showContent = true
                showStats = true
                showButtons = true
                HapticManager.celebrationSuccess()
            } else {
                startAnimation()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Program complete! \(programName). Certificate number \(certificateNumber)")
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
            showCertificate = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func shareToCircle() async {
        guard let share = onShareToCircle else { return }
        isSharing = true
        await share()
        withAnimation {
            hasSharedToCircle = true
        }
        isSharing = false
    }

    private func startAnimation() {
        // Confetti starts immediately
        showConfetti = true

        // Title fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
        }

        // Certificate unfurls
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showCertificate = true
        }

        // Stats appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                showStats = true
            }
        }

        // Buttons appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                showButtons = true
            }
            HapticManager.celebrationSuccess()
        }
    }
}

// MARK: - Stat Badge

private struct CelebrationStatBadge: View {
    let icon: String
    let value: String
    let label: String

    private let goldColor = Color(red: 0.85, green: 0.65, blue: 0.13)

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(goldColor)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(minWidth: 70)
    }
}

// MARK: - Preview

#Preview("Certificate Celebration") {
    ProgramCertificateCelebrationView(
        programName: "Anxiety Relief Program",
        certificateNumber: "MF-A1B2C3D4",
        completionStats: .init(
            daysCompleted: 21,
            longestStreak: 14,
            skipsUsed: 2,
            totalDays: 21
        ),
        onDismiss: {},
        onShareToCircle: nil,
        onShareExternally: nil
    )
}

#Preview("With Share Options") {
    ProgramCertificateCelebrationView(
        programName: "Better Sleep in 14 Days",
        certificateNumber: "MF-SLEEP123",
        completionStats: .init(
            daysCompleted: 14,
            longestStreak: 14,
            skipsUsed: 0,
            totalDays: 14
        ),
        onDismiss: {},
        onShareToCircle: { },
        onShareExternally: { }
    )
}
