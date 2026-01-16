import SwiftUI

/// Reusable feature comparison table for free vs premium tiers
struct FeatureComparisonView: View {
    private let features = [
        ("Unlimited Chat", "infinity"),
        ("All Exercises", "figure.stairs"),
        ("Premium Content", "sparkles"),
        ("Advanced Insights", "chart.line.uptrend.xyaxis"),
        ("Offline Access", "wifi.slash"),
        ("Priority Support", "headphones")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Feature")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                Text("Free")
                    .font(.headline)
                    .frame(width: 60, alignment: .center)
                    .padding()

                Text("Premium")
                    .font(.headline)
                    .frame(width: 70, alignment: .center)
                    .padding()
            }
            .background(Color(.secondarySystemBackground))

            Divider()

            // Feature rows
            ForEach(0..<features.count, id: \.self) { index in
                let (featureName, iconName) = features[index]

                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: iconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text(featureName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    // Free tier - X
                    HStack {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, alignment: .center)
                    .padding()

                    // Premium tier - checkmark
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
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
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        FeatureComparisonView()
        Spacer()
    }
    .padding()
}
