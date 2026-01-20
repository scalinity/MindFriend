import SwiftUI

struct StressSignatureView: View {
    @StateObject private var viewModel: StressSignatureViewModel
    @Environment(\.dismiss) private var dismiss

    init(dataService: SupabaseDataService) {
        _viewModel = StateObject(wrappedValue: StressSignatureViewModel(dataService: dataService))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let signature = viewModel.signature {
                if signature.hasSufficientData {
                    contentView(signature)
                } else {
                    insufficientDataView
                }
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Stress Signature")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.fetchSignature()
        }
        .refreshable {
            await viewModel.refreshSignature()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your patterns...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Unable to load patterns")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await viewModel.fetchSignature()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentView(_ signature: StressSignature) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your stress signature reveals \(signature.totalPatternCount) patterns from your wellness data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Last updated: \(signature.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Timeline overview (if we have enough data points)
                if !signature.patterns.isEmpty,
                   let firstPattern = signature.patterns.first,
                   !firstPattern.timeline.isEmpty {
                    SignatureTimelineView(
                        timeline: firstPattern.timeline,
                        title: "Pattern Evolution"
                    )
                }

                // Stress Triggers section
                if !signature.stressTriggers.isEmpty {
                    patternSection(
                        title: "Stress Triggers",
                        icon: "exclamationmark.triangle",
                        color: .orange,
                        patterns: signature.stressTriggers
                    )
                }

                // Coping Strategies section
                if !signature.copingStrategies.isEmpty {
                    patternSection(
                        title: "What Helps",
                        icon: "heart.circle",
                        color: .green,
                        patterns: signature.copingStrategies
                    )
                }

                // Time Patterns section
                if !signature.timePatterns.isEmpty {
                    patternSection(
                        title: "Time Patterns",
                        icon: "clock",
                        color: .blue,
                        patterns: signature.timePatterns
                    )
                }
            }
            .padding(.vertical)
        }
    }

    private func patternSection(
        title: String,
        icon: String,
        color: Color,
        patterns: [SignaturePattern]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)

            ForEach(patterns) { pattern in
                SignaturePatternCard(pattern: pattern)
                    .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No patterns detected yet")
                .font(.headline)

            Text("Keep logging your moods and using wellness features to discover your stress signature.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var insufficientDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Building your signature")
                .font(.headline)

            Text("We need a bit more data to create meaningful patterns. Keep tracking for at least 7 days.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Progress indicator could go here
            if let signature = viewModel.signature {
                VStack(spacing: 8) {
                    Text("\(signature.totalPatternCount) patterns detected so far")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: Double(signature.totalPatternCount), total: 3.0)
                        .frame(maxWidth: 200)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StressSignatureView(dataService: DependencyContainer().supabaseDataService)
    }
}
#endif
