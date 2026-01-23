// MindFriend Level-Up Celebration View
// Full-screen celebration animation when user levels up

import SwiftUI

struct LevelUpCelebrationView: View {
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
    let onDismiss: () -> Void
    
    @State private var showLevel = false
    @State private var showParticles = false
    @State private var showContent = false
    @State private var levelScale: CGFloat = 0.3
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            
            VStack(spacing: 32) {
                // Particle emitter
                if showParticles {
                    ParticleBurstView(
                        particleCount: 50,
                        colors: [.purple, .blue, .pink],
                        duration: 1.5
                    )
                    .frame(width: 300, height: 300)
                }
                
                // Level number with glow
                if showLevel {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.purple.opacity(0.3), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .blur(radius: 20)
                        
                        Text("\(newLevel)")
                            .font(.system(size: 80, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .scaleEffect(levelScale)
                }
                
                // Text content
                if showContent {
                    VStack(spacing: 12) {
                        Text("LEVEL UP!")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        
                        Text("Level \(oldLevel) → \(newLevel)")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            Text("+\(xpEarned) XP")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)
                        }
                        .padding(.top, 8)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                if showContent {
                    Text("Tap anywhere to continue")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top)
                }
            }
            .padding(40)
        }
        .onAppear {
            triggerAnimation()
            scheduleAutoDismiss()
        }
    }
    
    private func triggerAnimation() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Level animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            showLevel = true
            levelScale = 1.0
        }
        
        // Particles after 0.2s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                showParticles = true
            }
        }
        
        // Content after 0.6s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
        }
    }
    
    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onDismiss()
        }
    }
}
