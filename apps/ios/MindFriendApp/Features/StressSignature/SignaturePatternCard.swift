import SwiftUI

struct SignaturePatternCard: View {
    let pattern: SignaturePattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and category
            HStack {
                Image(systemName: pattern.type.iconName)
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.category)
                        .font(.headline)

                    Text(pattern.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Confidence badge
                confidenceBadge
            }

            // Stats row
            HStack(spacing: 16) {
                statItem(icon: "chart.bar.fill", label: "Frequency", value: pattern.frequencyDescription)
                statItem(icon: "number", label: "Evidence", value: "\(pattern.evidenceCount)")
                statItem(icon: "calendar", label: "Duration", value: "\(pattern.durationDays)d")
            }
            .font(.caption)

            // Top exercises (if available)
            if let exercises = pattern.topExercises, !exercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What helps:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(exercises, id: \.self) { exercise in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text(exercise)
                                .font(.caption)
                        }
                    }
                }
            }

            // Peak times (if available)
            if let times = pattern.peakTimes, !times.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Peak times:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(times.joined(separator: ", "))
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var confidenceBadge: some View {
        Text("\(pattern.confidencePercentage)%")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceBadgeColor.opacity(0.2))
            .foregroundColor(confidenceBadgeColor)
            .cornerRadius(8)
    }

    private var confidenceBadgeColor: Color {
        switch pattern.confidenceColor {
        case "green":
            return .green
        case "yellow":
            return .yellow
        case "orange":
            return .orange
        default:
            return .gray
        }
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    SignaturePatternCard(
        pattern: SignaturePattern(
            id: UUID(),
            category: "Work Stress",
            type: .stressTrigger,
            confidenceScore: 0.85,
            evidenceCount: 12,
            frequency: 3.2,
            timeline: [
                TimelineDataPoint(date: Date().addingTimeInterval(-30 * 24 * 60 * 60), count: 1),
                TimelineDataPoint(date: Date(), count: 12)
            ],
            firstDetected: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            lastDetected: Date(),
            topExercises: ["Deep Breathing", "Body Scan"],
            peakTimes: ["09:00", "17:00"]
        )
    )
    .padding()
}
#endif
