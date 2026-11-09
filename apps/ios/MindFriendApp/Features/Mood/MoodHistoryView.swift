import Charts
import SwiftUI

struct MoodHistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var moods: [MoodEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedDays = 14

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Period selector
                Picker("Period", selection: $selectedDays) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                // Chart
                if isLoading {
                    ProgressView()
                        .frame(height: 200)
                } else if let loadError {
                    SupportUnavailableState(
                        title: "Mood history unavailable", message: loadError,
                        actionTitle: "Try again", action: { Task { await loadMoods() } })
                } else if moods.isEmpty {
                    EmptyMoodHistoryView()
                } else {
                    MoodChart(moods: moods, selectedDays: selectedDays)
                        .frame(height: 200)
                        .padding()

                    // Stats
                    MoodStatsCard(moods: moods)
                        .padding(.horizontal)

                    // List
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Recent Entries")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal)

                        ForEach(moods.prefix(10)) { mood in
                            MoodHistoryRow(mood: mood)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Mood History")
        .task {
            await loadMoods()
        }
        .onChange(of: selectedDays) { _, _ in
            Task { await loadMoods() }
        }
    }

    private func loadMoods() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            moods = try await container.supabaseDataService.getMoodsForPast(days: selectedDays)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct MoodChart: View {
    let moods: [MoodEntry]
    let selectedDays: Int

    private var moodsWithDates: [(mood: MoodEntry, date: Date)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return moods.compactMap { mood in
            guard let date = formatter.date(from: mood.localDate) else { return nil }
            return (mood, date)
        }
    }

    var body: some View {
        Chart(moodsWithDates, id: \.mood.id) { item in
            LineMark(
                x: .value("Date", item.date),
                y: .value("Mood", item.mood.moodScore)
            )
            .foregroundStyle(SupportTheme.accent)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", item.date),
                y: .value("Mood", item.mood.moodScore)
            )
            .foregroundStyle(SupportTheme.accent)
        }
        .chartYScale(domain: 1...5)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                AxisGridLine()
                if selectedDays == 7 {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                } else {
                    AxisValueLabel(format: .dateTime.day())
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text(moodEmoji(for: score))
                    }
                }
            }
        }
    }

    private var xAxisStride: Int {
        switch selectedDays {
        case 7: return 1
        case 14: return 2
        case 30: return 7
        default: return 2
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return "😐"
        }
    }
}

struct MoodStatsCard: View {
    let moods: [MoodEntry]

    var averageMood: Double {
        guard !moods.isEmpty else { return 0 }
        return Double(moods.reduce(0) { $0 + $1.moodScore }) / Double(moods.count)
    }

    var bestDay: String? {
        moods.max(by: { $0.moodScore < $1.moodScore })?.localDate
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            StatBox(
                title: "Average",
                value: String(format: "%.1f", averageMood),
                icon: "chart.bar.fill"
            )

            StatBox(
                title: "Entries",
                value: "\(moods.count)",
                icon: "list.bullet"
            )

            if let best = bestDay {
                StatBox(
                    title: "Best Day",
                    value: formatDate(best),
                    icon: "star.fill"
                )
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.accent)

            Text(value)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(title)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
    }
}

struct MoodHistoryRow: View {
    let mood: MoodEntry

    var moodEmoji: String {
        switch mood.moodScore {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return "😐"
        }
    }

    var body: some View {
        HStack {
            Text(moodEmoji)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(mood.localDate)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let note = mood.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            HStack(spacing: SupportTheme.Spacing.xxs) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(index <= mood.moodScore ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .supportCard()
        .padding(.horizontal)
    }
}

struct EmptyMoodHistoryView: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No mood entries yet")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Start tracking your mood to see patterns")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(height: 200)
    }
}

#Preview {
    NavigationStack {
        MoodHistoryView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
