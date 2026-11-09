import SwiftUI

/// Reusable feature comparison table for free vs premium tiers
struct FeatureComparisonView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let features = [
        ("Unlimited Chat", "infinity"),
        ("All Exercises", "figure.stairs"),
        ("Premium Content", "sparkles"),
        ("Advanced Insights", "chart.line.uptrend.xyaxis"),
        ("Offline Access", "wifi.slash"),
        ("Priority Support", "headphones"),
    ]

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                Text("Features")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(features.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Label(features[index].0, systemImage: features[index].1)
                            .font(.headline)
                        Text("Free: Not included")
                            .foregroundStyle(SupportTheme.textSecondary)
                        Label("Premium: Included", systemImage: "checkmark")
                            .foregroundStyle(SupportTheme.accent)
                    }
                    .supportCard()
                    .accessibilityElement(children: .combine)
                }
            }
        } else {

            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Feature")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    Text("Free")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(width: 60, alignment: .center)
                        .padding()

                    Text("Premium")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(width: 70, alignment: .center)
                        .padding()
                }
                .background(SupportTheme.surface)

                Divider()

                // Feature rows
                ForEach(0..<features.count, id: \.self) { index in
                    let (featureName, iconName) = features[index]

                    HStack(spacing: 0) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: iconName)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .frame(width: 24)

                            Text(featureName)
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                        // Free tier - X
                        HStack {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .frame(width: 60, alignment: .center)
                        .padding()

                        // Premium tier - checkmark
                        HStack {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(SupportTheme.accent)
                        }
                        .frame(width: 70, alignment: .center)
                        .padding()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(featureName): Not included in free tier, included in premium")

                    if index < features.count - 1 {
                        Divider()
                    }
                }
            }
            .background(SupportTheme.canvas)
            .cornerRadius(SupportTheme.controlRadius)
            .overlay(
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .stroke(SupportTheme.separator, lineWidth: 1)
            )
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.l) {
        FeatureComparisonView()
        Spacer()
    }
    .padding()
}
