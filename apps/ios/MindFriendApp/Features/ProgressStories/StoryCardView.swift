import SwiftUI

/// Renders an individual story card with visual variants based on card type
/// Supports all 7 card types: streak, mood, exercise, quest, insight, minimal, milestone
struct StoryCardView: View {
    let card: StoryCard
    let privacyMode: Bool
    var isExport: Bool = false

    // Standard story card dimensions (9:16 aspect ratio for Instagram Stories)
    private let exportWidth: CGFloat = 1080
    private let exportHeight: CGFloat = 1920

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient based on variant
                backgroundGradient

                // Content
                VStack(spacing: 0) {
                    Spacer()

                    // Icon (if available)
                    cardIcon
                        .padding(.bottom, 24)

                    // Stat (if available)
                    if let stat = card.data.stat, !stat.isEmpty {
                        statView(stat: stat, label: card.data.statLabel)
                            .padding(.bottom, 16)
                    }

                    // Headline
                    Text(card.data.headline)
                        .font(.system(size: isExport ? 72 : 36, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)

                    // Message
                    Text(displayMessage)
                        .font(.system(size: isExport ? 36 : 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineLimit(4)

                    // Call to action (for minimal cards)
                    if let cta = card.data.callToAction, !cta.isEmpty {
                        ctaButton(title: cta)
                            .padding(.top, 24)
                    }

                    Spacer()

                    // Card type indicator (bottom)
                    cardTypeIndicator
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: isExport ? 0 : 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: card.variant.gradientColors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // Add subtle pattern overlay for celebration/milestone variants
            patternOverlay
        )
    }

    @ViewBuilder
    private var patternOverlay: some View {
        switch card.variant {
        case .celebration, .milestone:
            // Confetti-like dots pattern
            GeometryReader { geo in
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 20...60))
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var cardIcon: some View {
        Image(systemName: resolvedIconName)
            .font(.system(size: isExport ? 120 : 60, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private var resolvedIconName: String {
        if let dataIcon = card.data.icon, !dataIcon.isEmpty {
            return dataIconToSFSymbol(dataIcon)
        }
        return card.cardType.iconName
    }

    private func dataIconToSFSymbol(_ icon: String) -> String {
        switch icon {
        case "sparkles": return "sparkles"
        case "heart": return "heart.fill"
        case "leaf": return "leaf.fill"
        case "sun": return "sun.max.fill"
        case "star": return "star.fill"
        default: return card.cardType.iconName
        }
    }

    // MARK: - Stat View

    @ViewBuilder
    private func statView(stat: String, label: String?) -> some View {
        let displayStat = privacyMode ? "•••" : stat

        VStack(spacing: 4) {
            Text(displayStat)
                .font(.system(size: isExport ? 144 : 72, weight: .heavy))
                .foregroundStyle(.white)

            if let label = label, !label.isEmpty {
                Text(label)
                    .font(.system(size: isExport ? 28 : 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(2)
            }
        }
    }

    // MARK: - Call to Action

    @ViewBuilder
    private func ctaButton(title: String) -> some View {
        Text(title)
            .font(.system(size: isExport ? 32 : 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(.white.opacity(0.2))
            )
    }

    // MARK: - Card Type Indicator

    @ViewBuilder
    private var cardTypeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: card.cardType.iconName)
                .font(.system(size: isExport ? 24 : 12))

            Text(card.cardType.displayName)
                .font(.system(size: isExport ? 24 : 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
    }

    // MARK: - Privacy-Aware Message

    /// Cached regex pattern for privacy mode redaction (compiled once, reused)
    private static let numberRedactionPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\d+\\.?\\d*", options: [])
    }()

    private var displayMessage: String {
        guard privacyMode else { return card.data.message }

        // Redact specific content in privacy mode using cached regex
        var message = card.data.message

        // Redact numeric values (e.g., "3.8 average mood" -> "•• average mood")
        if let pattern = Self.numberRedactionPattern {
            let range = NSRange(message.startIndex..., in: message)
            message = pattern.stringByReplacingMatches(
                in: message,
                options: [],
                range: range,
                withTemplate: "••"
            )
        }

        return message
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []

        parts.append("\(card.cardType.displayName) card")
        parts.append(card.data.headline)

        if let stat = card.data.stat, !stat.isEmpty, !privacyMode {
            if let label = card.data.statLabel {
                parts.append("\(stat) \(label)")
            } else {
                parts.append(stat)
            }
        }

        parts.append(displayMessage)

        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview Provider

#Preview("Streak Card - Celebration") {
    StoryCardView(
        card: StoryCard(
            id: UUID(),
            cardType: .streak,
            variant: .celebration,
            data: StoryCardData(
                headline: "Unstoppable!",
                message: "You're crushing it! 28 days of consistent check-ins.",
                stat: "28",
                statLabel: "Day Streak",
                icon: nil,
                callToAction: nil,
                streakDays: 28,
                trend: nil,
                checkinCount: nil,
                moodMin: nil,
                moodMax: nil,
                exerciseCount: nil,
                exerciseMinutes: nil,
                questCount: nil,
                aiGenerated: nil,
                milestoneType: nil
            ),
            generatedAt: Date()
        ),
        privacyMode: false
    )
    .frame(width: 300, height: 533)
}

#Preview("Mood Card - Improving") {
    StoryCardView(
        card: StoryCard(
            id: UUID(),
            cardType: .mood,
            variant: .celebration,
            data: StoryCardData(
                headline: "Rising Up!",
                message: "Your mood is trending up! Small steps lead to big changes.",
                stat: "7.2",
                statLabel: "Average Mood",
                icon: nil,
                callToAction: nil,
                streakDays: nil,
                trend: "improving",
                checkinCount: 6,
                moodMin: 4.0,
                moodMax: 9.0,
                exerciseCount: nil,
                exerciseMinutes: nil,
                questCount: nil,
                aiGenerated: nil,
                milestoneType: nil
            ),
            generatedAt: Date()
        ),
        privacyMode: false
    )
    .frame(width: 300, height: 533)
}

#Preview("Minimal Card - Encouragement") {
    StoryCardView(
        card: StoryCard(
            id: UUID(),
            cardType: .minimal,
            variant: .encouragement,
            data: StoryCardData(
                headline: "Start Your Journey",
                message: "Welcome to your weekly story! Log activities to see your progress.",
                stat: nil,
                statLabel: nil,
                icon: "sparkles",
                callToAction: "Log Your First Mood",
                streakDays: nil,
                trend: nil,
                checkinCount: nil,
                moodMin: nil,
                moodMax: nil,
                exerciseCount: nil,
                exerciseMinutes: nil,
                questCount: nil,
                aiGenerated: nil,
                milestoneType: nil
            ),
            generatedAt: Date()
        ),
        privacyMode: false
    )
    .frame(width: 300, height: 533)
}

#Preview("Privacy Mode") {
    StoryCardView(
        card: StoryCard(
            id: UUID(),
            cardType: .mood,
            variant: .default,
            data: StoryCardData(
                headline: "Steady Progress",
                message: "Your 7.2 average mood shows stability.",
                stat: "7.2",
                statLabel: "Average Mood",
                icon: nil,
                callToAction: nil,
                streakDays: nil,
                trend: "stable",
                checkinCount: 5,
                moodMin: 6.0,
                moodMax: 8.0,
                exerciseCount: nil,
                exerciseMinutes: nil,
                questCount: nil,
                aiGenerated: nil,
                milestoneType: nil
            ),
            generatedAt: Date()
        ),
        privacyMode: true
    )
    .frame(width: 300, height: 533)
}
