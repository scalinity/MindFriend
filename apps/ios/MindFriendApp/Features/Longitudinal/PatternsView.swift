import SwiftUI

// MARK: - Patterns View

struct PatternsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = PatternsViewModel()
    @State private var selectedFilter: LongitudinalPatternType?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.patterns.isEmpty {
                    emptyStateView
                } else {
                    // Filter chips
                    filterSection

                    // Patterns list
                    patternsSection
                }
            }
            .padding()
        }
        .navigationTitle("Detected Patterns")
        .navigationBarTitleDisplayMode(.large)
        .task {
            viewModel.setService(container.longitudinalService)
            await viewModel.loadPatterns()
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LongitudinalFilterChip(
                    title: "All",
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                }

                ForEach(LongitudinalPatternType.allCases, id: \.self) { type in
                    LongitudinalFilterChip(
                        title: type.displayName,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                    }
                }
            }
        }
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredPatterns) { pattern in
                PatternDetailCard(pattern: pattern)
            }
        }
    }

    private var filteredPatterns: [LongitudinalPattern] {
        if let filter = selectedFilter {
            return viewModel.patterns.filter { $0.patternType == filter }
        }
        return viewModel.patterns
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Analyzing your patterns...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Patterns Detected Yet")
                .font(.headline)
            Text("Continue tracking your mood regularly. We'll identify patterns in your wellness journey once we have enough data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - View Model

@MainActor
final class PatternsViewModel: ObservableObject {
    @Published var patterns: [LongitudinalPattern] = []
    @Published var isLoading = false

    private var service: LongitudinalService?

    func setService(_ service: LongitudinalService) {
        self.service = service
    }

    func loadPatterns() async {
        guard let service else { return }

        isLoading = true

        do {
            patterns = try await service.fetchPatterns()
        } catch {
            // Handle silently
        }

        isLoading = false
    }
}

// MARK: - Pattern Detail Card

struct PatternDetailCard: View {
    let pattern: LongitudinalPattern

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: pattern.patternIcon)
                    .font(.title2)
                    .foregroundStyle(patternColor)
                    .frame(width: 40, height: 40)
                    .background(patternColor.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.patternType.displayName)
                        .font(.headline)
                    Text("Confidence: \(pattern.confidenceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ConfidenceIndicator(confidence: pattern.confidence)
            }

            // Description
            Text(pattern.patternDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Expanded details
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "First Detected", value: formattedDate(pattern.firstDetected))
                    DetailRow(label: "Last Detected", value: formattedDate(pattern.lastDetected))
                    DetailRow(label: "Occurrences", value: "\(pattern.occurrences)")
                }
            }

            // Toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private var patternColor: Color {
        switch pattern.patternType {
        case .seasonalMood: return .orange
        case .weeklyRhythm: return .blue
        case .eventResponse: return .purple
        case .improvementTrend: return .green
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views
// LongitudinalFilterChip is defined in LongitudinalComponents.swift

struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(confidenceColor)

            // Mini bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(confidenceColor)
                        .frame(width: geometry.size.width * confidence)
                }
            }
            .frame(width: 40, height: 4)
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .blue }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PatternsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PatternsView()
                .environmentObject(DependencyContainer.preview)
        }
    }
}
#endif
