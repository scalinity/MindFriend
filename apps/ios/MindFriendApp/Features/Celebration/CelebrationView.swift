import SwiftUI

/// Full-screen celebration modal shown when user hits a milestone
struct CelebrationView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let celebration: CelebrationEvent
    var onDismiss: (() -> Void)?

    @State private var showContent = false
    @State private var isSharing = false
    @State private var showShareSheet = false
    @State private var hasSharedToCircle = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: celebration.celebrationType.confettiColors + [.black.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.4)
            .ignoresSafeArea()

            // Dark overlay for readability
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Confetti particles
            ConfettiView(colors: celebration.celebrationType.confettiColors)

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Celebration icon
                ZStack {
                    // Glowing background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: celebration.celebrationType.confettiColors,
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)
                        .opacity(showContent ? 0.6 : 0)

                    // Icon container
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: celebration.celebrationType.confettiColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: celebration.celebrationType.confettiColors.first?.opacity(0.5) ?? .clear, radius: 20)

                    Image(systemName: celebration.displayIconName)
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                }
                .scaleEffect(showContent ? 1 : 0.3)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)

                // Title and subtitle
                VStack(spacing: 12) {
                    Text(celebration.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: showContent)

                    Text(celebration.subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: showContent)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    // Share to Circle button
                    Button {
                        Task { await shareToCircle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                            Text(hasSharedToCircle ? "Shared to Circle" : "Share with Circle")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(hasSharedToCircle ? Color.green : Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(hasSharedToCircle || isSharing || celebration.sharedToCircle)

                    // External share button
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Externally")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    }

                    // Continue button
                    Button {
                        dismissCelebration()
                    } label: {
                        Text("Continue")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: showContent)
            }
        }
        .onAppear {
            triggerHaptic()
            withAnimation {
                showContent = true
            }
            hasSharedToCircle = celebration.sharedToCircle
            markAsShown()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareCardSheet(celebration: celebration) {
                markAsSharedExternally()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Celebration: \(celebration.title). \(celebration.subtitle)")
        .accessibilityAddTraits(.isModal)
    }

    private func triggerHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func markAsShown() {
        Task {
            try? await container.supabaseDataService.markCelebrationShown(celebrationId: celebration.id)
            Analytics.shared.track(.celebrationShown, properties: [
                "type": celebration.celebrationType.rawValue,
                "value": celebration.value
            ])
        }
    }

    private func shareToCircle() async {
        isSharing = true
        defer { isSharing = false }

        do {
            _ = try await container.supabaseDataService.shareCelebrationToCircles(celebrationId: celebration.id)
            withAnimation {
                hasSharedToCircle = true
            }
        } catch {
            Log.data.error("[Celebration] Share to circle failed: \(error)")
        }
    }

    private func markAsSharedExternally() {
        Task {
            try? await container.supabaseDataService.markCelebrationSharedExternally(celebrationId: celebration.id)
        }
    }

    private func dismissCelebration() {
        Analytics.shared.track(.celebrationDismissed, properties: [
            "type": celebration.celebrationType.rawValue,
            "shared_to_circle": hasSharedToCircle
        ])
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss?()
            dismiss()
        }
    }
}

// MARK: - Confetti View

/// Animated confetti particles for celebration
struct ConfettiView: View {
    let colors: [Color]

    @State private var particles: [ConfettiParticle] = []
    @State private var animationPhase = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiShape(type: particle.shape)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size * 0.6)
                        .rotationEffect(.degrees(particle.rotation + (animationPhase ? particle.rotationSpeed : 0)))
                        .position(
                            x: particle.x + (animationPhase ? particle.driftX : 0),
                            y: animationPhase ? geo.size.height + 50 : particle.y
                        )
                        .opacity(animationPhase ? 0 : 1)
                }
            }
            .onAppear {
                createParticles(in: geo.size)
                withAnimation(.easeOut(duration: 3.5)) {
                    animationPhase = true
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func createParticles(in size: CGSize) {
        particles = (0..<80).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: -100...size.height * 0.3),
                size: CGFloat.random(in: 8...16),
                color: colors.randomElement() ?? .accentColor,
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: 180...720),
                driftX: CGFloat.random(in: -100...100),
                shape: ConfettiParticle.ParticleShape.allCases.randomElement() ?? .rectangle
            )
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let rotation: Double
    let rotationSpeed: Double
    let driftX: CGFloat
    let shape: ParticleShape

    enum ParticleShape: CaseIterable {
        case rectangle
        case circle
        case triangle
    }
}

struct ConfettiShape: Shape {
    let type: ConfettiParticle.ParticleShape

    func path(in rect: CGRect) -> Path {
        switch type {
        case .rectangle:
            return Rectangle().path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Celebration View Modifier

/// View modifier to show pending celebrations
struct CelebrationModifier: ViewModifier {
    @EnvironmentObject var container: DependencyContainer
    @Binding var pendingCelebrations: [CelebrationEvent]

    @State private var currentCelebration: CelebrationEvent?

    func body(content: Content) -> some View {
        content
            .onChange(of: pendingCelebrations) { _, newValue in
                if currentCelebration == nil, let first = newValue.first {
                    currentCelebration = first
                }
            }
            .fullScreenCover(item: $currentCelebration) { celebration in
                CelebrationView(celebration: celebration) {
                    // Remove shown celebration and show next
                    pendingCelebrations.removeAll { $0.id == celebration.id }
                    if let next = pendingCelebrations.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            currentCelebration = next
                        }
                    }
                }
                .environmentObject(container)
            }
    }
}

extension View {
    /// Shows celebration modals for pending celebrations
    func celebrationOverlay(pending: Binding<[CelebrationEvent]>) -> some View {
        modifier(CelebrationModifier(pendingCelebrations: pending))
    }
}

// MARK: - Preview

#Preview("Streak Milestone") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .streakMilestone,
            value: 30,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    )
    .environmentObject(DependencyContainer.preview)
}

#Preview("Level Up") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .levelUp,
            value: 10,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    )
    .environmentObject(DependencyContainer.preview)
}

#Preview("Badge Unlock") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .badgeUnlock,
            value: 1,
            badgeId: UUID(),
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date(),
            badgeTitle: "Week Warrior",
            badgeDescription: "Complete 7 days in a row",
            badgeIconName: "flame.fill"
        )
    )
    .environmentObject(DependencyContainer.preview)
}
