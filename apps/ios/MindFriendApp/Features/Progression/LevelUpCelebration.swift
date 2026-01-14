import SwiftUI

/// Celebratory overlay shown when user levels up
struct LevelUpCelebration: View {
    let newLevel: Int
    let newTitle: String
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showParticles = false
    @State private var particlePositions: [ParticlePosition] = []

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Particle effects
            ForEach(particlePositions) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(showParticles ? 0 : 1)
                    .animation(
                        .easeOut(duration: 2.0).delay(particle.delay),
                        value: showParticles
                    )
            }

            // Main content
            VStack(spacing: 24) {
                // Animated star burst
                ZStack {
                    ForEach(0..<8) { index in
                        Image(systemName: "star.fill")
                            .font(.title2)
                            .foregroundColor(.yellow)
                            .offset(y: showContent ? -60 : 0)
                            .opacity(showContent ? 0.8 : 0)
                            .rotationEffect(.degrees(Double(index) * 45))
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.5)
                                    .delay(0.1 + Double(index) * 0.05),
                                value: showContent
                            )
                    }

                    // Level badge
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.yellow, .orange],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: .yellow.opacity(0.5), radius: 20)

                        VStack(spacing: 0) {
                            Text("\(newLevel)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(showContent ? 1 : 0.3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showContent)
                }

                // Title text
                VStack(spacing: 8) {
                    Text("LEVEL UP!")
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: showContent)

                    Text(newTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: showContent)
                }

                // Encouragement text
                Text("Keep up the great work!")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: showContent)

                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(25)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.4).delay(0.5), value: showContent)
                .padding(.top, 16)
            }
        }
        .onAppear {
            generateParticles()
            withAnimation {
                showContent = true
            }
            // Trigger particle animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showParticles = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Congratulations! You've reached level \(newLevel), \(newTitle)")
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func generateParticles() {
        let colors: [Color] = [.yellow, .orange, .white, .pink, .purple]

        particlePositions = (0..<30).map { _ in
            ParticlePosition(
                x: CGFloat.random(in: -150...150),
                y: CGFloat.random(in: -200...200),
                size: CGFloat.random(in: 4...12),
                color: colors.randomElement()!,
                delay: Double.random(in: 0...0.5)
            )
        }
    }
}

struct ParticlePosition: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let delay: Double
}

/// View modifier for showing level-up celebration
struct LevelUpCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let level: Int
    let title: String

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                LevelUpCelebration(
                    newLevel: level,
                    newTitle: title,
                    onDismiss: { isPresented = false }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }
}

extension View {
    /// Shows a level-up celebration overlay
    func levelUpCelebration(
        isPresented: Binding<Bool>,
        level: Int,
        title: String
    ) -> some View {
        modifier(LevelUpCelebrationModifier(
            isPresented: isPresented,
            level: level,
            title: title
        ))
    }
}

#Preview {
    ZStack {
        // Background content
        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        Text("Main Content")
            .foregroundColor(.white)
    }
    .levelUpCelebration(
        isPresented: .constant(true),
        level: 5,
        title: "Explorer"
    )
}

#Preview("Level 10") {
    LevelUpCelebration(
        newLevel: 10,
        newTitle: "Seeker",
        onDismiss: {}
    )
}

#Preview("Level 25") {
    LevelUpCelebration(
        newLevel: 25,
        newTitle: "Sage",
        onDismiss: {}
    )
}
