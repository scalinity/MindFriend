// SOSButton.swift
// MindFriend - Prominent SOS Panic Button

import SwiftUI

/// Prominent emergency button for the home screen
struct SOSButton: View {
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulsing outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.red.opacity(0.6), .orange.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 76, height: 76)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)

                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.7, green: 0.1, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)

                // Content
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)

                    Text("SOS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
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
            .easeOut(duration: 1.5)
            .repeatForever(autoreverses: false)
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
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                Text("SOS")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
    VStack(spacing: 40) {
        SOSButton { }

        CompactSOSButton { }
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
