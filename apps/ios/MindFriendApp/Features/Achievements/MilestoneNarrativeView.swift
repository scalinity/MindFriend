// MindFriend Milestone Narrative View
// Display AI-generated personalized milestone story

import SwiftUI

struct MilestoneNarrativeView: View {
    let celebration: MilestoneCelebration
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Level badge
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: .purple.opacity(0.5), radius: 20)
                        
                        VStack(spacing: 4) {
                            Text("LEVEL")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.8))
                            Text("\(celebration.levelReached)")
                                .font(.system(size: 36, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    // Title
                    Text("Your Journey So Far")
                        .font(.title2.bold())
                    
                    // Narrative
                    Text(celebration.narrative)
                        .font(.body)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Journey stats highlights
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(
                            icon: "checkmark.circle.fill",
                            value: "\(celebration.journeyStats.totalQuests)",
                            label: "Quests",
                            color: .green
                        )
                        StatCard(
                            icon: "figure.mind.and.body",
                            value: "\(celebration.journeyStats.totalExercises)",
                            label: "Exercises",
                            color: .blue
                        )
                        StatCard(
                            icon: "heart.fill",
                            value: "\(celebration.journeyStats.totalMoodLogs)",
                            label: "Mood Logs",
                            color: .pink
                        )
                        StatCard(
                            icon: "flame.fill",
                            value: "\(celebration.journeyStats.longestStreak)",
                            label: "Best Streak",
                            color: .orange
                        )
                    }
                    
                    // Share button
                    Button {
                        generateShareCard()
                    } label: {
                        Label("Share Your Journey", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Milestone Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }
    
    private func generateShareCard() {
        let renderer = ImageRenderer(content: MilestoneShareCard(celebration: celebration))
        renderer.scale = 3.0
        
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3.bold())
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MilestoneShareCard: View {
    let celebration: MilestoneCelebration
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [.purple, .blue, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 20) {
                Spacer()
                
                Text("LEVEL \(celebration.levelReached)")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
                
                Text(celebration.narrativeExcerpt)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .lineLimit(4)
                
                HStack(spacing: 16) {
                    ShareStatBadge(icon: "checkmark.circle", value: "\(celebration.journeyStats.totalQuests)")
                    ShareStatBadge(icon: "flame", value: "\(celebration.journeyStats.longestStreak)")
                    ShareStatBadge(icon: "star", value: "\(celebration.journeyStats.badgesEarned)")
                }
                
                Spacer()
                
                Text("MindFriend Wellness Journey")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 20)
            }
            .padding(40)
        }
        .frame(width: 400, height: 500)
    }
}

struct ShareStatBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
