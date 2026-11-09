//
//  ProgramsCertificateStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Completion certificates
//

import SwiftUI

/// Step 4: Show the completion certificate reward
struct ProgramsCertificateStep: View {
    let onComplete: () -> Void

    @State private var showCertificate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TutorialStepView(
            icon: "rosette",
            iconColor: SupportTheme.Celebration.gold,
            headline: "Earn Certificates",
            subheadline: "Complete a program to earn a certificate that celebrates your achievement.",
            primaryLabel: "Explore Programs",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(SupportTheme.Celebration.gold)
                        .accessibilityHidden(true)

                    Text("Certificate of completion")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("21-Day Anxiety Reset")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text("Completed January 2026")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Label("+500 XP", systemImage: "medal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SupportTheme.textPrimary)
                        .padding(.horizontal, SupportTheme.Spacing.s)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.elevated, in: Capsule())
                }
                .padding(SupportTheme.Spacing.l)
                .frame(maxWidth: .infinity)
                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .strokeBorder(SupportTheme.Celebration.gold, lineWidth: 2)
                )
                .scaleEffect(showCertificate || reduceMotion ? 1 : 0.95)
                .opacity(showCertificate ? 1 : 0)
                .padding(.horizontal, SupportTheme.Spacing.l)

                Text("Share your achievements and see how far you have come.")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .opacity(showCertificate ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(0.2)) {
                    showCertificate = true
                }
            }
        }
    }
}

#Preview {
    ProgramsCertificateStep(onComplete: {})
}
