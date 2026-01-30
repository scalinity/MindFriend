// MindFriend Badge Stamp Effect
// Hexagonal badge stamp-down animation with impact ripple

import SwiftUI

/// Hexagonal badge with stamp-down animation and impact ripple
struct BadgeStampEffect: View {
    let tierColor: Color
    let sfSymbol: String
    let onImpact: (() -> Void)?

    @State private var stampOffset: CGFloat = -100
    @State private var stampScale: CGFloat = 0.3
    @State private var showRipples = false
    @State private var iconRotation: Double = -30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tierColor: Color, sfSymbol: String, onImpact: (() -> Void)? = nil) {
        self.tierColor = tierColor
        self.sfSymbol = sfSymbol
        self.onImpact = onImpact
    }

    var body: some View {
        ZStack {
            // Concentric hexagonal ripples (behind badge)
            if showRipples {
                ForEach(0..<3, id: \.self) { index in
                    HexagonShape()
                        .stroke(tierColor.opacity(0.4 - Double(index) * 0.1), lineWidth: 2)
                        .frame(width: rippleSize(for: index), height: rippleSize(for: index))
                        .scaleEffect(showRipples ? 1.5 + CGFloat(index) * 0.3 : 0.8)
                        .opacity(showRipples ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 0.8)
                                .delay(Double(index) * 0.1),
                            value: showRipples
                        )
                }
            }

            // Main hexagonal badge
            ZStack {
                // Hexagon background with metallic gradient
                HexagonShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                tierColor.opacity(0.9),
                                tierColor,
                                tierColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: tierColor.opacity(0.5), radius: 15, x: 0, y: 5)

                // Inner hexagon highlight (metallic sheen)
                HexagonShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .frame(width: 100, height: 100)

                // Badge icon
                Image(systemName: sfSymbol)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(iconRotation))
            }
            .offset(y: stampOffset)
            .scaleEffect(stampScale)
        }
        .onAppear {
            if reduceMotion {
                // Instant appearance for reduced motion
                stampOffset = 0
                stampScale = 1
                iconRotation = 0
                showRipples = true
            } else {
                animateStamp()
            }
        }
    }

    private func rippleSize(for index: Int) -> CGFloat {
        140 + CGFloat(index) * 30
    }

    private func animateStamp() {
        // Stamp down animation with spring overshoot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
            stampOffset = 0
            stampScale = 1
            iconRotation = 0
        }

        // Trigger ripples and haptic on impact
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            HapticManager.badgeStamp()
            onImpact?()

            withAnimation {
                showRipples = true
            }

            // Secondary ripple haptic
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                HapticManager.badgeRipple()
            }
        }
    }
}

// MARK: - Hexagon Shape

/// Custom hexagon shape for badge
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let centerY = rect.midY

        // Flat-top hexagon
        let radius = min(width, height) / 2
        var path = Path()

        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let x = centerX + radius * cos(angle)
            let y = centerY + radius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview

#Preview("Bronze Badge") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeStampEffect(
            tierColor: Color(hex: "#CD7F32") ?? .orange,
            sfSymbol: "star.fill"
        )
    }
}

#Preview("Gold Badge") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeStampEffect(
            tierColor: Color(hex: "#FFD700") ?? .yellow,
            sfSymbol: "flame.fill"
        )
    }
}

#Preview("Diamond Badge") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeStampEffect(
            tierColor: Color(hex: "#B9F2FF") ?? .cyan,
            sfSymbol: "crown.fill"
        )
    }
}

#Preview("Legendary Badge") {
    ZStack {
        Color.black.ignoresSafeArea()
        BadgeStampEffect(
            tierColor: Color(hex: "#9400D3") ?? .purple,
            sfSymbol: "sparkles"
        )
    }
}
