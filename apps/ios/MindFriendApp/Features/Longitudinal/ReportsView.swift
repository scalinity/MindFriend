import SwiftUI

// MARK: - Reports View

struct ReportsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = ReportsViewModel()
    @State private var showingGenerateSheet = false

    var body: some View {
        List {
            if viewModel.isLoading {
                loadingSection
            } else if viewModel.reports.isEmpty {
                emptyStateSection
            } else {
                reportsSection
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingGenerateSheet = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            GenerateReportSheet(viewModel: viewModel)
        }
        .refreshable {
            await viewModel.loadReports()
        }
        .task {
            viewModel.setService(container.longitudinalService)
            await viewModel.loadReports()
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading reports...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 40)
        }
    }

    // MARK: - Empty State Section

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Reports Yet")
                    .font(.headline)
                Text("Generate your first wellness report to see insights about your journey over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingGenerateSheet = true
                } label: {
                    Text("Generate Report")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Reports Section

    private var reportsSection: some View {
        ForEach(groupedReports.keys.sorted().reversed(), id: \.self) { year in
            Section(header: Text(String(year))) {
                ForEach(groupedReports[year] ?? []) { report in
                    NavigationLink(destination: ReportDetailView(report: report)) {
                        ReportRow(report: report)
                    }
                }
            }
        }
    }

    private var groupedReports: [Int: [LongitudinalReport]] {
        Dictionary(grouping: viewModel.reports) { report in
            Calendar.current.component(.year, from: report.generatedAt)
        }
    }
}

// MARK: - View Model

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var reports: [LongitudinalReport] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var error: String?

    private var service: LongitudinalService?

    func setService(_ service: LongitudinalService) {
        self.service = service
    }

    func loadReports() async {
        guard let service else { return }

        isLoading = true

        do {
            reports = try await service.fetchReports()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func generateReport(type: ReportType, startDate: Date?, endDate: Date?) async {
        guard let service else { return }

        isGenerating = true

        do {
            var timePeriod: TimePeriod?
            if let start = startDate, let end = endDate {
                timePeriod = TimePeriod(start: start, end: end)
            }

            let newReport = try await service.generateReport(type: type, timePeriod: timePeriod)
            reports.insert(newReport, at: 0)
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
    }
}

// MARK: - Report Row

struct ReportRow: View {
    let report: LongitudinalReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.reportType.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(report.reportType.displayName)
                    .font(.headline)
                Text(report.formattedPeriod)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Generated \(report.formattedGeneratedAt)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Generate Report Sheet

struct GenerateReportSheet: View {
    @ObservedObject var viewModel: ReportsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ReportType = .quarterly
    @State private var useCustomDates = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Report Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(reportDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectedType == .custom {
                    Section("Date Range") {
                        DatePicker(
                            "Start Date",
                            selection: $startDate,
                            in: ...endDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "End Date",
                            selection: $endDate,
                            in: startDate...Date(),
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's in a report?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Your report will include:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ReportFeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Mood trends and patterns")
                            ReportFeatureRow(icon: "calendar", text: "Activity heatmap")
                            ReportFeatureRow(icon: "lightbulb", text: "Key insights")
                            ReportFeatureRow(icon: "star", text: "Personalized recommendations")
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Generate Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        Task {
                            await viewModel.generateReport(
                                type: selectedType,
                                startDate: selectedType == .custom ? startDate : nil,
                                endDate: selectedType == .custom ? endDate : nil
                            )
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isGenerating)
                }
            }
            .overlay {
                if viewModel.isGenerating {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Generating your report...")
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var reportDescription: String {
        switch selectedType {
        case .quarterly:
            return "Covers the last 3 complete months"
        case .annual:
            return "Covers the last 12 complete months"
        case .custom:
            return "Select your own date range (up to 24 months)"
        }
    }
}

struct ReportFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Report Detail View

struct ReportDetailView: View {
    let report: LongitudinalReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.reportType.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(report.formattedPeriod)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary")
                        .font(.headline)
                    Text(report.contentJson.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)

                // Key Insights
                if !report.contentJson.keyInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Insights")
                            .font(.headline)

                        ForEach(report.contentJson.keyInsights, id: \.self) { insight in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                Text(insight)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                }

                // Charts section
                chartsSection

                // Recommendations
                if !report.contentJson.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recommendations")
                            .font(.headline)

                        ForEach(report.contentJson.recommendations.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)
                                Text(report.contentJson.recommendations[index])
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                }
            }
            .padding()
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(
                    item: reportText,
                    subject: Text("MindFriend \(report.reportType.displayName)"),
                    message: Text("My wellness report from MindFriend")
                )
            }
        }
    }

    @ViewBuilder
    private var chartsSection: some View {
        if !report.contentJson.chartsData.moodTrend.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mood Trend")
                    .font(.headline)

                ReportMoodTrendChart(data: report.contentJson.chartsData.moodTrend)
                    .frame(height: 200)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }

        if !report.contentJson.chartsData.activityHeatmap.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity Heatmap")
                    .font(.headline)

                ActivityHeatmapView(data: report.contentJson.chartsData.activityHeatmap)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
    }

    private var reportText: String {
        """
        MindFriend \(report.reportType.displayName)
        Period: \(report.formattedPeriod)

        Summary:
        \(report.contentJson.summary)

        Key Insights:
        \(report.contentJson.keyInsights.map { "- \($0)" }.joined(separator: "\n"))

        Recommendations:
        \(report.contentJson.recommendations.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
    }
}

// MARK: - Report Charts

struct ReportMoodTrendChart: View {
    let data: [MoodDataPoint]

    var body: some View {
        // Simple line representation
        GeometryReader { geometry in
            let maxY: Double = 5
            let minY: Double = 1
            let range = maxY - minY

            Path { path in
                guard data.count > 1 else { return }

                let stepX = geometry.size.width / CGFloat(data.count - 1)

                for (index, point) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat((point.value - minY) / range))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Gradient fill
            Path { path in
                guard data.count > 1 else { return }

                let stepX = geometry.size.width / CGFloat(data.count - 1)

                path.move(to: CGPoint(x: 0, y: geometry.size.height))

                for (index, point) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat((point.value - minY) / range))
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct ActivityHeatmapView: View {
    let data: [ActivityDataPoint]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(data, id: \.week) { point in
                RoundedRectangle(cornerRadius: 4)
                    .fill(activityColor(for: point.days))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(height: 100)
    }

    private func activityColor(for days: Int) -> Color {
        switch days {
        case 7: return .green
        case 5...6: return .green.opacity(0.7)
        case 3...4: return .green.opacity(0.4)
        case 1...2: return .green.opacity(0.2)
        default: return Color(.systemGray5)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReportsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReportsView()
                .environmentObject(DependencyContainer.preview)
        }
    }
}
#endif
