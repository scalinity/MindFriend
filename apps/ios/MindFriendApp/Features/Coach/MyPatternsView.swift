import SwiftUI
import Charts

@MainActor
final class MyPatternsViewModel: ObservableObject {
    @Published var analytics: PatternAnalytics?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var distortionLibrary: [CognitiveDistortion] = []

    private let coachService: CoachServiceProtocol

    init(coachService: CoachServiceProtocol) {
        self.coachService = coachService
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let analyticsTask = coachService.getMyPatterns()
            async let libraryTask = coachService.getDistortionLibrary()

            let (loadedAnalytics, loadedLibrary) = await (analyticsTask, libraryTask)

            await MainActor.run {
                self.analytics = loadedAnalytics
                self.distortionLibrary = loadedLibrary
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Unable to load patterns. Check your connection."
            }
        }
    }

    func distortionName(for code: String) -> String {
        distortionLibrary.first(where: { $0.code == code })?.name ?? code
    }

    func getDistortionColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .pink]
        return colors[index % colors.count]
    }
}

struct MyPatternsView: View {
    @StateObject private var viewModel: MyPatternsViewModel
    @Environment(\.dismiss) var dismiss

    init(coachService: CoachServiceProtocol) {
        _viewModel = StateObject(wrappedValue: MyPatternsViewModel(coachService: coachService))
    }

    var body: some View {
        NavigationStack {
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading your patterns...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if let analytics = viewModel.analytics {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with totals
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Thinking Patterns")
                                .font(.title2)
                                .fontWeight(.bold)

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This Week")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(analytics.last7Days)")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This Month")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(analytics.last30Days)")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // Top distortions chart
                        if !analytics.mostCommon.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Most Common Patterns")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 16) {
                                    ForEach(Array(analytics.mostCommon.prefix(5).enumerated()), id: \.element.code) { index, stat in
                                        DistortionBarView(
                                            name: viewModel.distortionName(for: stat.code),
                                            count: stat.count,
                                            percentage: stat.percentage,
                                            color: viewModel.getDistortionColor(for: index),
                                            trend: stat.trend
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        }

                        // Pie chart of all distortions
                        if !analytics.byDistortionType.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pattern Distribution")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                Chart(Array(analytics.byDistortionType.enumerated()), id: \.element.code) { index, stat in
                                    SectorMark(
                                        angle: .value("Count", stat.count),
                                        innerRadius: .ratio(0.618),
                                        angularInset: 1.5
                                    )
                                    .foregroundStyle(viewModel.getDistortionColor(for: index).gradient)
                                    .opacity(0.8)
                                }
                                .frame(height: 250)
                                .padding(.horizontal, 16)

                                // Legend
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(analytics.byDistortionType.enumerated()), id: \.element.code) { index, stat in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(viewModel.getDistortionColor(for: index).gradient)
                                                .frame(width: 12, height: 12)

                                            Text(viewModel.distortionName(for: stat.code))
                                                .font(.caption)

                                            Spacer()

                                            Text("\(stat.count)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        }

                        // Insights section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Insights & Next Steps")
                                .font(.headline)
                                .padding(.horizontal, 16)

                            VStack(alignment: .leading, spacing: 12) {
                                if analytics.last7Days > 0 {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.yellow)
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Keep an eye on your top patterns")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Text("Notice when they appear and try the suggested reframes.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.blue)
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("No patterns detected yet")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Text("Keep chatting! Patterns will show up as you engage.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 16)

                        // Learn more button
                        NavigationLink(destination: DistortionLibraryView(library: viewModel.distortionLibrary)) {
                            HStack(spacing: 8) {
                                Image(systemName: "book.fill")
                                Text("Learn About Thinking Patterns")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Unable to Load Patterns")
                        .font(.headline)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: {
                        Task {
                            await viewModel.loadData()
                        }
                    }) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("My Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadData()
            }
        }
    }
}

// MARK: - Distortion Bar View

struct DistortionBarView: View {
    let name: String
    let count: Int
    let percentage: Double
    let color: Color
    let trend: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 2) {
                    if trend == "increasing" {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .foregroundColor(.red)
                    } else if trend == "decreasing" {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.gray)
                    }

                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray6))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                Text("\(Int(percentage * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(trend.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Distortion Library View

struct DistortionLibraryView: View {
    let library: [CognitiveDistortion]
    @State private var searchText = ""

    var filteredLibrary: [CognitiveDistortion] {
        if searchText.isEmpty {
            return library
        }
        return library.filter { distortion in
            distortion.name.localizedCaseInsensitiveContains(searchText) ||
            distortion.shortDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            SearchBar(text: $searchText, placeholder: "Search patterns...")

            ForEach(filteredLibrary, id: \.code) { distortion in
                NavigationLink(destination: DistortionDetailView(distortion: distortion)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(distortion.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(distortion.shortDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Thinking Patterns Library")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Distortion Detail View

struct DistortionDetailView: View {
    let distortion: CognitiveDistortion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(distortion.name)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(distortion.shortDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Full description
                VStack(alignment: .leading, spacing: 8) {
                    Text("What it means")
                        .font(.headline)

                    Text(distortion.fullDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(16)

                // Examples
                if !distortion.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common examples")
                            .font(.headline)

                        ForEach(distortion.examples, id: \.self) { example in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\"")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)

                                Text(example)
                                    .font(.body)
                                    .italic()

                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                }

                // Reframe templates
                if !distortion.reframeTemplates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to reframe it")
                            .font(.headline)

                        ForEach(distortion.reframeTemplates, id: \.self) { template in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                    .frame(width: 20)

                                Text(template)
                                    .font(.body)

                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                }

                Spacer()
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(distortion.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Search Bar Helper

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    MyPatternsView(coachService: MockCoachService())
}
