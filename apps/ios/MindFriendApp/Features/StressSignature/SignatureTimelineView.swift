import SwiftUI
import Charts

struct SignatureTimelineView: View {
    let timeline: [TimelineDataPoint]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            if timeline.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .padding(.vertical)
    }

    private var chart: some View {
        Chart(timeline) { dataPoint in
            LineMark(
                x: .value("Date", dataPoint.date),
                y: .value("Count", dataPoint.count)
            )
            .foregroundStyle(.blue.gradient)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", dataPoint.date),
                y: .value("Count", dataPoint.count)
            )
            .foregroundStyle(.blue)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 200)
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No timeline data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    SignatureTimelineView(
        timeline: [
            TimelineDataPoint(date: Date().addingTimeInterval(-30 * 24 * 60 * 60), count: 1),
            TimelineDataPoint(date: Date().addingTimeInterval(-20 * 24 * 60 * 60), count: 3),
            TimelineDataPoint(date: Date().addingTimeInterval(-10 * 24 * 60 * 60), count: 7),
            TimelineDataPoint(date: Date(), count: 12)
        ],
        title: "Pattern Timeline"
    )
}
#endif
