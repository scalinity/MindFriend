// SOSButton.swift
// MindFriend - Prominent SOS Panic Button

import SwiftUI

/// Prominent emergency button for the home screen
struct SOSButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulsing outer ring
                Circle()
                    .stroke(
                        SupportTheme.surface,
                        lineWidth: 3
                    )
                    .frame(width: 76, height: 76)
                    .scaleEffect(reduceMotion ? 1 : (pulseScale))
                    .opacity(pulseOpacity)

                // Main button
                Circle()
                    .fill(
                        SupportTheme.surface
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)

                // Content
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text("SOS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SupportTheme.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SOS Panic Button")
        .accessibilityHint("Tap for immediate calming support during anxiety or panic")
        .onAppear {
            startPulseAnimation()
        }
    }

    private func startPulseAnimation() {
        // Use SwiftUI's built-in repeating animation (no Timer needed)
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : (.easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false))
        ) {
            pulseScale = 1.15
            pulseOpacity = 0.0
        }
    }
}

// MARK: - Compact SOS Button

/// Smaller SOS button for navigation bar or persistent access
struct CompactSOSButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                Text("SOS")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(Color.red)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SOS Panic Button")
        .accessibilityHint("Tap for immediate calming support")
    }
}

#Preview("SOS Button") {
    VStack(spacing: SupportTheme.Spacing.xl) {
        SOSButton {}

        CompactSOSButton {}
    }
    .padding()
    .background(SupportTheme.canvas)
}
