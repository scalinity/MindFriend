import SwiftUI
import Charts

/// 7-day sleep trend graph
struct SleepTrendGraph: View {
    let entries: [SleepEntry]

    private var chartData: [(date: Date, score: Int)] {
        entries.compactMap { entry in
            guard let score = entry.sleepScore else { return nil }
            return (entry.date, score)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        if chartData.isEmpty {
            emptyState
        } else {
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(chartData, id: \.date) { data in
                LineMark(
                    x: .value("Date", data.date, unit: .day),
                    y: .value("Score", data.score)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", data.date, unit: .day),
                    y: .value("Score", data.score)
                )
                .foregroundStyle(.blue)
            }

            // Target line at 80
            RuleMark(y: .value("Target", 80))
                .foregroundStyle(.green.opacity(0.3))
                .lineStyle(StrokeStyle(dash: [5, 5]))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 80, 100]) { value in
                AxisValueLabel()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack {
            Text("Not enough data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()

    let entries = (0..<7).map { dayOffset in
        let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
        return SleepEntry(
            id: UUID(),
            userId: UUID(),
            date: date,
            source: .healthkit,
            bedtime: calendar.date(byAdding: .hour, value: -8, to: date)!,
            wakeTime: date,
            timeInBedMinutes: 480,
            timeAsleepMinutes: 420,
            deepSleepMinutes: nil,
            remSleepMinutes: nil,
            lightSleepMinutes: nil,
            awakeMinutes: nil,
            sleepEfficiency: nil,
            heartRateAvg: nil,
            heartRateMin: nil,
            hrvAvg: nil,
            respiratoryRate: nil,
            userRating: nil,
            dreamNotes: nil,
            notes: nil,
            sleepScore: Int.random(in: 60...95),
            scoreBreakdown: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    return SleepTrendGraph(entries: entries)
        .frame(height: 150)
        .padding()
}
