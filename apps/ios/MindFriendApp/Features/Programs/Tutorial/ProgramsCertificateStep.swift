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
    @State private var showSparkles = false

    var body: some View {
        TutorialStepView(
            icon: "rosette",
            iconColor: .yellow,
            headline: "Earn Certificates",
            subheadline: "Complete a program to earn a certificate that celebrates your achievement.",
            primaryLabel: "Explore Programs",
            primaryAction: onComplete
        ) {
            VStack(spacing: 16) {
                // Certificate preview
                ZStack {
                    // Background sparkles
                    if showSparkles {
                        ForEach(0..<8, id: \.self) { i in
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundStyle(.yellow.opacity(0.6))
                                .offset(
                                    x: CGFloat.random(in: -80...80),
                                    y: CGFloat.random(in: -60...60)
                                )
                                .scaleEffect(CGFloat.random(in: 0.5...1.0))
                        }
                    }

                    // Certificate card
                    VStack(spacing: 8) {
                        // Seal
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)

                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                        // Certificate text
                        VStack(spacing: 8) {
                            Text("Certificate of Completion")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("21-Day Anxiety Reset")
                                .font(.headline)

                            Text("Completed January 2026")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        // Badge
                        HStack(spacing: 6) {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(.orange)
                            Text("+500 XP")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.yellow.opacity(0.5), .orange.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .scaleEffect(showCertificate ? 1 : 0.8)
                    .opacity(showCertificate ? 1 : 0)
                }
                .padding(.horizontal, 24)

                // Benefits
                Text("Share your achievements and track your growth journey!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .opacity(showCertificate ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
                    showCertificate = true
                }
                withAnimation(.easeInOut(duration: 0.5).delay(0.6)) {
                    showSparkles = true
                }
            }
        }
    }
}

#Preview {
    ProgramsCertificateStep(onComplete: {})
}
