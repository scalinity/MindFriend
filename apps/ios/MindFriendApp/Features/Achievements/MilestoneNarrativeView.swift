import SwiftUI

struct MilestoneNarrativeView: View {
    let celebration: MilestoneCelebration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                CelebrationParticles().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.l) {
                        CelebrationEmblem(.text("\(celebration.levelReached)"), tint: SupportTheme.Celebration.gold, diameter: 100)
                        Text("Your journey so far").font(.title.bold()).accessibilityAddTraits(.isHeader)
                        Text(celebration.narrative)
                            .font(.body).lineSpacing(SupportTheme.Spacing.xxs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .supportCard()
                            .celebrationReveal(delay: 0.2)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3),
                                  spacing: SupportTheme.Spacing.s) {
                            MilestoneStatCard(icon: "target", value: "\(celebration.journeyStats.totalQuests)", label: "Quests done", color: SupportTheme.accent)
                            MilestoneStatCard(icon: "trophy", value: "\(celebration.journeyStats.badgesEarned)", label: "Badges earned", color: SupportTheme.Celebration.gold)
                            MilestoneStatCard(icon: "checkmark.circle", value: "\(celebration.levelReached)", label: "Current level", color: SupportTheme.accent)
                        }
                        Button { generateShareCard() } label: {
                            Label("Share Your Journey", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.supportPrimary)
                    }
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(maxWidth: SupportTheme.readableWidth)
                    .padding(SupportTheme.Spacing.m)
                    .frame(maxWidth: .infinity)
                }
            }
            .supportScreen()
            .navigationTitle("Milestone Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage { ShareSheet(items: [image]).supportSheet() }
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

struct MilestoneStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
            Text(value).font(.title3.bold()).foregroundStyle(SupportTheme.textPrimary)
            Text(label).font(.caption).foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .supportCard()
        .accessibilityElement(children: .combine)
    }
}

struct MilestoneShareCard: View {
    let celebration: MilestoneCelebration

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            CelebrationEmblem(.text("\(celebration.levelReached)"), tint: SupportTheme.Celebration.gold, animated: false)
            Text("Level \(celebration.levelReached)").font(.largeTitle.bold())
            Text(celebration.narrativeExcerpt).font(.title3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SupportTheme.Spacing.m) {
                ShareStatBadge(icon: "checkmark.circle", value: "\(celebration.journeyStats.totalQuests)")
                ShareStatBadge(icon: "star", value: "\(celebration.journeyStats.badgesEarned)")
            }
            Text("MindFriend wellness journey").font(.caption).foregroundStyle(SupportTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(SupportTheme.textPrimary)
        .padding(SupportTheme.Spacing.xl)
        .frame(width: 400)
        .background(SupportTheme.canvas)
    }
}

struct ShareStatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        Label(value, systemImage: icon)
            .font(.headline).foregroundStyle(SupportTheme.textPrimary)
            .padding(SupportTheme.Spacing.s)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
}
