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
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingGenerateSheet = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Create report")
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
                VStack(spacing: SupportTheme.Spacing.s) {
                    ProgressView()
                    Text("Loading reports...")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, SupportTheme.Spacing.xl)
        }
        .listRowBackground(SupportTheme.surface)
    }

    // MARK: - Empty State Section

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: SupportTheme.Spacing.m) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(SupportTheme.textSecondary)
                Text("No Reports Yet")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Generate your first wellness report to see insights about your journey over time.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingGenerateSheet = true
                } label: {
                    Text("Generate Report")
                }
                .buttonStyle(.supportPrimary)
            }
            .padding(.vertical, SupportTheme.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(SupportTheme.surface)
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
            .listRowBackground(SupportTheme.surface)
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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: report.reportType.icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.Area.insights.palette.ink)
                .frame(width: 40, height: 40)
                .background(SupportTheme.Area.insights.palette.tint)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(report.reportType.displayName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(report.formattedPeriod)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                Text("Generated \(report.formattedGeneratedAt)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
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
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .listRowBackground(SupportTheme.surface)

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
                    .listRowBackground(SupportTheme.surface)
                }

                Section {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("What's in a report?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Your report will include:")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            ReportFeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Mood trends and patterns")
                            ReportFeatureRow(icon: "calendar", text: "Activity heatmap")
                            ReportFeatureRow(icon: "lightbulb", text: "Key insights")
                            ReportFeatureRow(icon: "star", text: "Personalized recommendations")
                        }
                    }
                    .padding(.vertical, SupportTheme.Spacing.xs)
                }

                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
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
                        SupportTheme.canvas.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: SupportTheme.Spacing.m) {
                            ProgressView()
                            Text("Generating your report...")
                                .font(.subheadline)
                        }
                        .padding(SupportTheme.Spacing.l)
                        .background(SupportTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
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
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.Area.insights.palette.ink)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

// MARK: - Report Detail View

struct ReportDetailView: View {
    let report: LongitudinalReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text(report.reportType.displayName)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)
                    Text(report.formattedPeriod)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Summary
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Summary")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(report.contentJson.summary)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .supportCard()
                .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)

                // Key Insights
                if !report.contentJson.keyInsights.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Key Insights")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(report.contentJson.keyInsights, id: \.self) { insight in
                            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(SupportTheme.Celebration.gold)
                                Text(insight)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .supportCard()
                    .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
                }

                // Charts section
                chartsSection

                // Recommendations
                if !report.contentJson.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Recommendations")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(report.contentJson.recommendations.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(SupportTheme.Area.insights.palette.ink)
                                Text(report.contentJson.recommendations[index])
                                    .font(.subheadline)
                            }
                        }
                    }
                    .supportCard()
                    .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Mood Trend")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ReportMoodTrendChart(data: report.contentJson.chartsData.moodTrend)
                    .frame(height: 200)
            }
            .supportCard()
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
        }

        if !report.contentJson.chartsData.activityHeatmap.isEmpty {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Activity Heatmap")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ActivityHeatmapView(data: report.contentJson.chartsData.activityHeatmap)
            }
            .supportCard()
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
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
                    colors: [SupportTheme.Area.insights.palette.tint, SupportTheme.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

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
            .stroke(SupportTheme.Area.insights.palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct ActivityHeatmapView: View {
    let data: [ActivityDataPoint]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: SupportTheme.Spacing.xxs), count: 7),
            spacing: SupportTheme.Spacing.xxs
        ) {
            ForEach(data, id: \.week) { point in
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .fill(activityColor(for: point.days))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(height: 100)
    }

    private func activityColor(for days: Int) -> Color {
        switch days {
        case 7: return SupportTheme.Status.positive
        case 5...6: return SupportTheme.Status.positive.opacity(0.7)
        case 3...4: return SupportTheme.Status.positive.opacity(0.4)
        case 1...2: return SupportTheme.Status.positive.opacity(0.2)
        default: return SupportTheme.field
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
