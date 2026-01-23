// MindFriend Tier Progress View
// Shows tiered badge progression (bronze → silver → gold → diamond)

import SwiftUI

struct TierProgressView: View {
    let badge: AchievementBadge
    let progress: UserBadgeProgress?
    
    private var tierChain: [BadgeTier] {
        // Build tier chain from current badge
        if let tier = badge.tier {
            switch tier {
            case .bronze:
                return [.bronze, .silver, .gold, .diamond]
            case .silver:
                return [.bronze, .silver, .gold, .diamond]
            case .gold:
                return [.bronze, .silver, .gold, .diamond]
            case .diamond:
                return [.bronze, .silver, .gold, .diamond]
            case .legendary:
                return [.bronze, .silver, .gold, .diamond, .legendary]
            }
        }
        return []
    }
    
    private var currentTierIndex: Int {
        guard let tier = badge.tier else { return 0 }
        return tierChain.firstIndex(of: tier) ?? 0
    }
    
    private var hasNextTier: Bool {
        currentTierIndex < tierChain.count - 1
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Tier timeline
            HStack(spacing: 8) {
                ForEach(Array(tierChain.enumerated()), id: \.offset) { index, tier in
                    TierBadgeView(
                        tier: tier,
                        isUnlocked: index <= currentTierIndex,
                        isCurrent: index == currentTierIndex
                    )
                    
                    if index < tierChain.count - 1 {
                        Rectangle()
                            .fill(index < currentTierIndex ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal)
            
            // Progress to next tier
            if hasNextTier, let nextTier = tierChain[safe: currentTierIndex + 1] {
                VStack(spacing: 8) {
                    HStack {
                        Text("Progress to \(nextTier.displayName)")
                            .font(.subheadline.bold())
                        
                        Spacer()
                        
                        if let target = progress?.progressTarget {
                            Text("\(progress?.progressCurrent ?? 0)/\(target)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    ProgressView(value: progress?.progressPercentage ?? 0)
                        .tint(Color(hex: nextTier.color) ?? .accentColor)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !hasNextTier {
                // Max tier reached
                Label("Max Tier Reached!", systemImage: "crown.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct TierBadgeView: View {
    let tier: BadgeTier
    let isUnlocked: Bool
    let isCurrent: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? (Color(hex: tier.color) ?? .gray) : Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if isUnlocked {
                    Image(systemName: isCurrent ? "star.fill" : "checkmark")
                        .foregroundStyle(.white)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.gray)
                        .font(.caption)
                }
            }
            
            Text(tier.displayName)
                .font(.caption2)
                .foregroundStyle(isUnlocked ? .primary : .secondary)
        }
    }
}
