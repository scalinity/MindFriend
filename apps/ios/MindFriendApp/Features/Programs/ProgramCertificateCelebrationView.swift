// MindFriend Program Certificate Celebration View
// Full celebration view for program completion with certificate

import SwiftUI

/// Full-screen celebration for program completion with certificate display, on the shared reward kit.
struct ProgramCertificateCelebrationView: View {
    let programName: String
    let certificateNumber: String
    let completionStats: CompletionStats
    let onDismiss: () -> Void
    let onShareToCircle: (() async -> Void)?
    let onShareExternally: (() -> Void)?

    @State private var isSharing = false
    @State private var hasSharedToCircle = false

    struct CompletionStats {
        let daysCompleted: Int
        let longestStreak: Int
        let skipsUsed: Int
        let totalDays: Int
    }

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
            CelebrationParticles().ignoresSafeArea()

            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol("checkmark.seal.fill"), tint: SupportTheme.Celebration.gold, diameter: 112)

                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Program complete")
                            .font(.largeTitle.bold())
                            .foregroundStyle(SupportTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("You finished \(programName).")
                            .font(.body)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
                    .celebrationReveal(delay: 0.2)

                    certificateCard
                        .celebrationReveal(delay: 0.3)

                    HStack(spacing: SupportTheme.Spacing.l) {
                        CelebrationStatBadge(icon: "calendar.badge.checkmark", value: "\(completionStats.daysCompleted)", label: "Days")
                        CelebrationStatBadge(icon: "arrow.triangle.2.circlepath", value: "\(completionStats.skipsUsed)", label: "Skips used")
                    }
                    .celebrationReveal(delay: 0.35)

                    VStack(spacing: SupportTheme.Spacing.s) {
                        Button("Continue") { onDismiss() }
                            .buttonStyle(.supportPrimary)
                        if onShareToCircle != nil {
                            Button {
                                Task { await shareToCircle() }
                            } label: {
                                Label(hasSharedToCircle ? "Shared with your circle" : "Share with your circle",
                                      systemImage: hasSharedToCircle ? "checkmark" : "person.2")
                            }
                            .buttonStyle(.supportSecondary)
                            .disabled(hasSharedToCircle || isSharing)
                        }
                        if let onShareExternally {
                            Button {
                                onShareExternally()
                            } label: {
                                Label("Share elsewhere", systemImage: "square.and.arrow.up")
                            }
                            .font(.subheadline)
                            .frame(minHeight: SupportTheme.minimumTarget)
                        }
                    }
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.bottom, SupportTheme.Spacing.l)
                    .celebrationReveal(delay: 0.45)
                }
                .padding(.top, SupportTheme.Spacing.xl)
                .frame(maxWidth: SupportTheme.readableWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { HapticManager.celebrationSuccess() }
        .accessibilityAddTraits(.isModal)
    }

    private var certificateCard: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text("Certificate of completion")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SupportTheme.textSecondary)
            Text(programName)
                .font(.title3.bold())
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Completed \(Date().formatted(date: .long, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
            Text("Certificate #\(certificateNumber)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .strokeBorder(SupportTheme.Celebration.gold, lineWidth: 3)
        )
        .padding(.horizontal, SupportTheme.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    private func shareToCircle() async {
        guard let share = onShareToCircle else { return }
        isSharing = true
        await share()
        hasSharedToCircle = true
        isSharing = false
    }
}

private struct CelebrationStatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SupportTheme.Celebration.gold)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(SupportTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

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
