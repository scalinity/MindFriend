import SwiftUI
import Charts

struct MoodHistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var moods: [MoodEntry] = []
    @State private var isLoading = true
    @State private var selectedDays = 14

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Period selector
                Picker("Period", selection: $selectedDays) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Chart
                if isLoading {
                    ProgressView()
                        .frame(height: 200)
                } else if moods.isEmpty {
                    EmptyMoodHistoryView()
                } else {
                    MoodChart(moods: moods)
                        .frame(height: 200)
                        .padding()

                    // Stats
                    MoodStatsCard(moods: moods)
                        .padding(.horizontal)

                    // List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Entries")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(moods.prefix(10)) { mood in
                            MoodHistoryRow(mood: mood)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
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
        defer { isLoading = false }

        do {
            moods = try await container.supabaseDataService.getMoodsForPast(days: selectedDays)
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

struct MoodChart: View {
    let moods: [MoodEntry]

    var body: some View {
        Chart(moods) { mood in
            LineMark(
                x: .value("Date", mood.localDate),
                y: .value("Mood", mood.moodScore)
            )
            .foregroundStyle(Color.accentColor)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", mood.localDate),
                y: .value("Mood", mood.moodScore)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text(moodEmoji(for: score))
                    }
                }
            }
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😢"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return ""
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
        HStack(spacing: 16) {
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

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MoodHistoryRow: View {
    let mood: MoodEntry

    var moodEmoji: String {
        switch mood.moodScore {
        case 1: return "😢"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    var body: some View {
        HStack {
            Text(moodEmoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(mood.localDate)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let note = mood.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(index <= mood.moodScore ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct EmptyMoodHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("No mood entries yet")
                .font(.headline)

            Text("Start tracking your mood to see patterns")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
