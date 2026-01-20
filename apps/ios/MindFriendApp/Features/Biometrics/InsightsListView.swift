import SwiftUI

struct InsightsListView: View {
    let insights: [BiometricInsight]
    @ObservedObject var healthKit: HealthKitService
    @State private var selectedInsight: BiometricInsight?

    var body: some View {
        List {
            ForEach(insights) { insight in
                InsightCard(
                    icon: insight.insightCategory.icon,
                    title: insight.title,
                    description: insight.description,
                    color: categoryColor(for: insight.insightCategory)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onTapGesture {
                    selectedInsight = insight
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let insight = insights[index]
                    Task {
                        try? await healthKit.dismissInsight(insight.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("All Insights")
        .sheet(item: $selectedInsight) { insight in
            InsightDetailView(insight: insight, healthKit: healthKit)
        }
    }

    private func categoryColor(for category: BiometricInsight.InsightCategory) -> Color {
        switch category {
        case .sleep: return .indigo
        case .activity: return .green
        case .stress: return .orange
        case .general: return .blue
        }
    }
}

struct InsightDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let insight: BiometricInsight
    @ObservedObject var healthKit: HealthKitService

    @State private var rating: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: insight.insightCategory.icon)
                            .font(.title)
                            .foregroundStyle(categoryColor)

                        VStack(alignment: .leading) {
                            Text(insight.insightCategory.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(insight.title)
                                .font(.title2.bold())
                        }
                    }

                    // Correlation badge
                    if let label = insight.correlationLabel {
                        HStack {
                            Text(label)
                                .font(.caption.bold())
                            Text("correlation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(categoryColor.opacity(0.2))
                        .clipShape(Capsule())
                    }

                    // Description
                    Text(insight.description)
                        .font(.body)

                    // Data info
                    if let dataPoints = insight.dataPointsCount {
                        HStack {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .foregroundStyle(.secondary)
                            Text("Based on \(dataPoints) days of data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let confidence = insight.confidenceScore {
                        HStack {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(.secondary)
                            Text("Confidence: \(Int(confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Rating
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Was this insight helpful?")
                            .font(.subheadline.bold())

                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundStyle(star <= rating ? .yellow : .gray)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveRating()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("Dismiss", role: .destructive) {
                        dismissInsight()
                    }
                }
            }
            .task {
                // Mark as read
                if !insight.isRead {
                    try? await healthKit.markInsightRead(insight.id)
                }
            }
        }
    }

    private var categoryColor: Color {
        switch insight.insightCategory {
        case .sleep: return .indigo
        case .activity: return .green
        case .stress: return .orange
        case .general: return .blue
        }
    }

    private func saveRating() {
        guard rating > 0 else { return }
        Task {
            try? await supabase
                .from("biometric_insights")
                .update(["user_rating": rating])
                .eq("id", value: insight.id)
                .execute()
        }
    }

    private func dismissInsight() {
        Task {
            try? await healthKit.dismissInsight(insight.id)
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        InsightsListView(insights: [], healthKit: HealthKitService())
    }
}
