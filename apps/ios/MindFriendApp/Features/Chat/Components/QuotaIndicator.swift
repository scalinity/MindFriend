import SwiftUI

// MARK: - Quota Level

/// Represents the quota level state based on remaining messages
private enum QuotaLevel {
    case critical  // 0-1 remaining
    case low       // 2 remaining
    case healthy   // 3+ remaining

    init(remaining: Int) {
        if remaining <= 1 {
            self = .critical
        } else if remaining <= 2 {
            self = .low
        } else {
            self = .healthy
        }
    }

    var progressColor: Color {
        switch self {
        case .critical: return .red
        case .low: return .orange
        case .healthy: return .blue
        }
    }

    var textColor: Color {
        switch self {
        case .critical: return .red
        case .low: return .orange
        case .healthy: return .secondary
        }
    }

    var accessibilityValue: String {
        switch self {
        case .critical, .low: return "Low quota"
        case .healthy: return "Healthy"
        }
    }

    var showUpgrade: Bool {
        switch self {
        case .critical, .low: return true
        case .healthy: return false
        }
    }
}

// MARK: - Quota Indicator

/// A visual indicator showing the user's remaining daily AI chat quota.
/// Shows a progress bar and remaining count, with upgrade prompt when low.
struct QuotaIndicator: View {
    let remaining: Int
    let total: Int
    let isPremium: Bool
    let onUpgrade: () -> Void

    private var quotaLevel: QuotaLevel { QuotaLevel(remaining: remaining) }

    var body: some View {
        if isPremium {
            // Premium users don't see quota indicator
            EmptyView()
        } else {
            quotaContent
        }
    }

    @ViewBuilder
    private var quotaContent: some View {
        HStack(spacing: 8) {
            // Visual progress bar (shows remaining, not used)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    // Progress fill (shows remaining quota)
                    Capsule()
                        .fill(quotaLevel.progressColor)
                        .frame(width: geometry.size.width * progressPercentage)
                }
            }
            .frame(width: 50, height: 6)

            // Text indicator
            Text("\(remaining) left")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(quotaLevel.textColor)

            // Upgrade button when low
            if quotaLevel.showUpgrade {
                Button(action: onUpgrade) {
                    Text("Upgrade")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                }
                .accessibilityLabel("Upgrade to premium")
                .accessibilityHint("Opens subscription options")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remaining) of \(total) chat messages remaining")
        .accessibilityValue(quotaLevel.accessibilityValue)
    }

    // MARK: - Computed Properties

    /// Shows remaining quota (fills from right to left as quota depletes)
    private var progressPercentage: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0, Double(remaining) / Double(total)))
    }
}

// MARK: - Compact Quota Badge

/// A more compact quota indicator for tight spaces
struct QuotaBadge: View {
    let remaining: Int
    let total: Int
    let isPremium: Bool

    private var quotaLevel: QuotaLevel { QuotaLevel(remaining: remaining) }

    var body: some View {
        if isPremium {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.caption2)
                Text("\(remaining)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(quotaLevel.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(quotaLevel.textColor.opacity(0.15))
            .cornerRadius(12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(remaining) chat messages remaining")
            .accessibilityValue(quotaLevel.accessibilityValue)
        }
    }
}

// MARK: - Preview

#Preview("Quota Indicator - Full") {
    VStack(spacing: 20) {
        QuotaIndicator(remaining: 5, total: 5, isPremium: false, onUpgrade: {})
        QuotaIndicator(remaining: 3, total: 5, isPremium: false, onUpgrade: {})
        QuotaIndicator(remaining: 2, total: 5, isPremium: false, onUpgrade: {})
        QuotaIndicator(remaining: 1, total: 5, isPremium: false, onUpgrade: {})
        QuotaIndicator(remaining: 0, total: 5, isPremium: false, onUpgrade: {})
        QuotaIndicator(remaining: 5, total: 5, isPremium: true, onUpgrade: {})
    }
    .padding()
}

#Preview("Quota Badge") {
    HStack(spacing: 16) {
        QuotaBadge(remaining: 5, total: 5, isPremium: false)
        QuotaBadge(remaining: 2, total: 5, isPremium: false)
        QuotaBadge(remaining: 1, total: 5, isPremium: false)
    }
    .padding()
}
