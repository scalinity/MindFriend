import SwiftUI
import Charts

// MARK: - Yearly Overview View

struct YearlyOverviewView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = YearlyOverviewViewModel()
    @State private var selectedYear: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    loadingView
                } else {
                    // Year selector
                    yearSelector

                    // 12-month mood chart
                    moodChartSection

                    // Seasonal comparison
                    if let patterns = viewModel.selectedYearStat?.seasonalPatterns {
                        seasonalComparisonSection(patterns)
                    }

                    // Year-over-year comparison
                    if viewModel.yearlyStats.count > 1 {
                        yearOverYearSection
                    }

                    // Milestones achieved
                    if let milestones = viewModel.selectedYearStat?.milestonesAchieved,
                       !milestones.isEmpty {
                        milestonesSection(milestones)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Yearly Overview")
        .navigationBarTitleDisplayMode(.large)
        .task {
            viewModel.setService(container.longitudinalService)
            await viewModel.loadData()
            if selectedYear == nil {
                selectedYear = viewModel.yearlyStats.first?.year
            }
        }
        .onChange(of: selectedYear) { _, newYear in
            if let year = newYear {
                viewModel.selectYear(year)
            }
        }
    }

    // MARK: - Year Selector

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.availableYears, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        Text(String(year))
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                selectedYear == year
                                    ? Color.blue
                                    : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(selectedYear == year ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Mood Chart Section

    private var moodChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mood Throughout the Year")
                .font(.headline)

            if viewModel.monthlyStatsForYear.isEmpty {
                Text("No mood data available for this year")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(viewModel.monthlyStatsForYear) { stat in
                        if let mood = stat.avgMood {
                            LineMark(
                                x: .value("Month", stat.monthStart, unit: .month),
                                y: .value("Mood", mood)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Month", stat.monthStart, unit: .month),
                                y: .value("Mood", mood)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Month", stat.monthStart, unit: .month),
                                y: .value("Mood", mood)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(moodLabel(for: intValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 250)
            }

            // Monthly stats list
            if !viewModel.monthlyStatsForYear.isEmpty {
                Divider()

                ForEach(viewModel.monthlyStatsForYear.reversed()) { stat in
                    MonthlyStatRow(stat: stat)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Seasonal Comparison

    private func seasonalComparisonSection(_ patterns: SeasonalPatterns) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seasonal Patterns")
                .font(.headline)

            // Season bars
            VStack(spacing: 12) {
                ForEach(patterns.allSeasons, id: \.name) { season in
                    SeasonRow(name: season.name, value: season.value)
                }
            }

            // Insight
            if let highest = patterns.highestSeason,
               let lowest = patterns.lowestSeason {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Your mood tends to be highest in \(highest.capitalized) and lowest in \(lowest.capitalized)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Year-over-Year Section

    private var yearOverYearSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Year-over-Year Comparison")
                .font(.headline)

            if viewModel.yearlyStats.count >= 2 {
                Chart {
                    ForEach(viewModel.yearlyStats.prefix(3)) { yearStat in
                        ForEach(0..<4, id: \.self) { quarter in
                            if yearStat.quarterlyMoods.indices.contains(quarter),
                               let mood = yearStat.quarterlyMoods[quarter] {
                                BarMark(
                                    x: .value("Quarter", "Q\(quarter + 1)"),
                                    y: .value("Mood", mood)
                                )
                                .foregroundStyle(by: .value("Year", String(yearStat.year)))
                                .position(by: .value("Year", String(yearStat.year)))
                            }
                        }
                    }
                }
                .chartYScale(domain: 1...5)
                .frame(height: 200)
            }

            // Comparison summary
            if let current = viewModel.selectedYearStat,
               let comparison = current.yearlyComparison {
                HStack(spacing: 24) {
                    ComparisonStat(
                        title: "Mood Change",
                        value: comparison.moodDeltaFormatted,
                        isPositive: comparison.isImprovement
                    )

                    if let activeDelta = comparison.activeDaysDelta {
                        ComparisonStat(
                            title: "Active Days",
                            value: activeDelta >= 0 ? "+\(Int(activeDelta))%" : "\(Int(activeDelta))%",
                            isPositive: activeDelta >= 0
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Milestones Section

    private func milestonesSection(_ milestones: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Milestones Achieved")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(milestones, id: \.name) { milestone in
                    MilestoneCard(milestone: milestone)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading yearly data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Helpers

    private func moodLabel(for value: Int) -> String {
        switch value {
        case 1: return "Low"
        case 2: return ""
        case 3: return "Mid"
        case 4: return ""
        case 5: return "High"
        default: return ""
        }
    }
}

// MARK: - View Model

@MainActor
final class YearlyOverviewViewModel: ObservableObject {
    @Published var yearlyStats: [YearlyStat] = []
    @Published var monthlyStats: [MonthlyStat] = []
    @Published var selectedYearStat: YearlyStat?
    @Published var isLoading = false

    private var service: LongitudinalService?

    var availableYears: [Int] {
        yearlyStats.map(\.year).sorted(by: >)
    }

    var monthlyStatsForYear: [MonthlyStat] {
        guard let year = selectedYearStat?.year else { return [] }

        let calendar = Calendar.current
        return monthlyStats.filter { stat in
            calendar.component(.year, from: stat.monthStart) == year
        }.sorted { $0.monthStart < $1.monthStart }
    }

    func setService(_ service: LongitudinalService) {
        self.service = service
    }

    func loadData() async {
        guard let service else { return }

        isLoading = true

        do {
            async let yearlyTask = service.fetchYearlyStats()
            async let monthlyTask = service.fetchMonthlyStats(limit: 36)

            let (yearly, monthly) = try await (yearlyTask, monthlyTask)
            yearlyStats = yearly
            monthlyStats = monthly

            if selectedYearStat == nil {
                selectedYearStat = yearly.first
            }
        } catch {
            // Handle error silently for now
        }

        isLoading = false
    }

    func selectYear(_ year: Int) {
        selectedYearStat = yearlyStats.first { $0.year == year }
    }
}

// MARK: - Supporting Views

struct MonthlyStatRow: View {
    let stat: MonthlyStat

    var body: some View {
        HStack {
            Text(stat.formattedMonth)
                .font(.subheadline)

            Spacer()

            if let mood = stat.avgMood {
                HStack(spacing: 4) {
                    Image(systemName: stat.trendIcon)
                        .font(.caption)
                        .foregroundStyle(Color(stat.trendColor))
                    Text(String(format: "%.1f", mood))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let pct = stat.activeDaysPct {
                Text("\(Int(pct))% active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SeasonRow: View {
    let name: String
    let value: Double

    private var seasonIcon: String {
        switch name.lowercased() {
        case "winter": return "snowflake"
        case "spring": return "leaf"
        case "summer": return "sun.max"
        case "fall": return "wind"
        default: return "circle"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: seasonIcon)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            Text(name.capitalized)
                .font(.subheadline)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(seasonColor(for: name))
                        .frame(width: geometry.size.width * CGFloat(value / 5.0))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1f", value))
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func seasonColor(for season: String) -> Color {
        switch season.lowercased() {
        case "winter": return .blue
        case "spring": return .green
        case "summer": return .orange
        case "fall": return .brown
        default: return .gray
        }
    }
}

struct ComparisonStat: View {
    let title: String
    let value: String
    let isPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isPositive ? .green : .red)
        }
    }
}

struct MilestoneCard: View {
    let milestone: Milestone

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: milestoneIcon)
                .font(.title2)
                .foregroundStyle(.yellow)

            Text(milestone.name)
                .font(.caption)
                .multilineTextAlignment(.center)

            Text(milestone.achievedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var milestoneIcon: String {
        switch milestone.type.lowercased() {
        case "badge": return "star.fill"
        case "streak": return "flame.fill"
        case "completion": return "checkmark.seal.fill"
        default: return "trophy.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct YearlyOverviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            YearlyOverviewView()
                .environmentObject(DependencyContainer.preview)
        }
    }
}
#endif
