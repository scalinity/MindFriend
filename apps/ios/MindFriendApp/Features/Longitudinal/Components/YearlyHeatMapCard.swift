//
//  YearlyHeatMapCard.swift
//  MindFriendApp
//
//  Yearly mood heat map calendar showing daily mood data
//

import SwiftUI

/// A heat map calendar showing mood data for the year
struct YearlyHeatMapCard: View {
    let moodsByDate: [String: Int] // date string (yyyy-MM-dd) to mood score
    let year: Int

    @State private var selectedMonth: Int? = nil

    private let calendar = Calendar.current
    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Yearly Heat Map")
                    .font(.headline)
                Spacer()
                Text(String(year))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Month grid - 4 columns x 3 rows
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(0..<12, id: \.self) { monthIndex in
                    MonthMiniHeatMap(
                        month: monthIndex + 1,
                        year: year,
                        moodsByDate: moodsByDate,
                        monthName: monthNames[monthIndex],
                        isSelected: selectedMonth == monthIndex
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedMonth == monthIndex {
                                selectedMonth = nil
                            } else {
                                selectedMonth = monthIndex
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                Spacer()
                HeatMapLegendItem(color: .green.opacity(0.8), label: "Great")
                HeatMapLegendItem(color: .yellow.opacity(0.8), label: "Good")
                HeatMapLegendItem(color: .orange.opacity(0.8), label: "Low")
                HeatMapLegendItem(color: Color(.systemGray5), label: "No data")
                Spacer()
            }
            .padding(.top, 4)

            // Selected month detail
            if let monthIndex = selectedMonth {
                MonthDetailView(
                    month: monthIndex + 1,
                    year: year,
                    moodsByDate: moodsByDate,
                    monthName: monthNames[monthIndex]
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

// MARK: - Month Mini Heat Map

private struct MonthMiniHeatMap: View {
    let month: Int
    let year: Int
    let moodsByDate: [String: Int]
    let monthName: String
    let isSelected: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            // Mini grid for month (simplified - just show ~5 weeks)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                    Rectangle()
                        .fill(colorForDay(day))
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
            }

            Text(monthName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(6)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var daysInMonth: [Int] {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return Array(1...28)
        }

        // Get first weekday offset (pad with 0s for alignment)
        let firstWeekday = calendar.component(.weekday, from: date)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Int] = Array(repeating: 0, count: offset)
        days.append(contentsOf: Array(range))

        // Pad to fill complete weeks (up to 6 weeks = 42 days)
        while days.count < 35 {
            days.append(0)
        }

        return days
    }

    private func colorForDay(_ day: Int) -> Color {
        guard day > 0 else { return Color.clear }

        let dateString = String(format: "%04d-%02d-%02d", year, month, day)
        guard let mood = moodsByDate[dateString] else {
            return Color(.systemGray5)
        }

        return moodColor(for: mood)
    }

    private func moodColor(for score: Int) -> Color {
        switch score {
        case 1...2: return .orange.opacity(0.8)
        case 3: return .yellow.opacity(0.8)
        case 4...5: return .green.opacity(0.8)
        default: return Color(.systemGray5)
        }
    }
}

// MARK: - Month Detail View

private struct MonthDetailView: View {
    let month: Int
    let year: Int
    let moodsByDate: [String: Int]
    let monthName: String

    private let calendar = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(monthName) \(String(year))")
                .font(.subheadline.weight(.semibold))

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                    if day > 0 {
                        DayCell(day: day, mood: moodForDay(day))
                    } else {
                        Color.clear
                            .frame(height: 28)
                    }
                }
            }

            // Stats for the month
            HStack {
                VStack(alignment: .leading) {
                    Text("\(daysWithData)")
                        .font(.title3.weight(.semibold))
                    Text("days tracked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let avg = averageMood {
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f", avg))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(moodColor(for: Int(avg.rounded())))
                        Text("avg mood")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var daysInMonth: [Int] {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return Array(1...28)
        }

        let firstWeekday = calendar.component(.weekday, from: date)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Int] = Array(repeating: 0, count: offset)
        days.append(contentsOf: Array(range))

        return days
    }

    private func moodForDay(_ day: Int) -> Int? {
        let dateString = String(format: "%04d-%02d-%02d", year, month, day)
        return moodsByDate[dateString]
    }

    private var daysWithData: Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 0
        }

        return range.filter { day in
            let dateString = String(format: "%04d-%02d-%02d", year, month, day)
            return moodsByDate[dateString] != nil
        }.count
    }

    private var averageMood: Double? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return nil
        }

        let moods = range.compactMap { day -> Int? in
            let dateString = String(format: "%04d-%02d-%02d", year, month, day)
            return moodsByDate[dateString]
        }

        guard !moods.isEmpty else { return nil }
        return Double(moods.reduce(0, +)) / Double(moods.count)
    }

    private func moodColor(for score: Int) -> Color {
        switch score {
        case 1...2: return .orange
        case 3: return .yellow
        case 4...5: return .green
        default: return .secondary
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let day: Int
    let mood: Int?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .frame(height: 28)

            Text("\(day)")
                .font(.caption2)
                .foregroundStyle(mood != nil ? .white : .secondary)
        }
    }

    private var backgroundColor: Color {
        guard let mood = mood else {
            return Color(.systemGray6)
        }

        switch mood {
        case 1...2: return .orange.opacity(0.8)
        case 3: return .yellow.opacity(0.8)
        case 4...5: return .green.opacity(0.8)
        default: return Color(.systemGray6)
        }
    }
}

// MARK: - Legend Item

private struct HeatMapLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        YearlyHeatMapCard(
            moodsByDate: PreviewData.sampleMoodsByDate,
            year: 2026
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

private enum PreviewData {
    static var sampleMoodsByDate: [String: Int] {
        var moods: [String: Int] = [:]
        let _ = Calendar.current

        // Generate sample data for current year
        for month in 1...12 {
            for day in 1...28 {
                // Random mood with some patterns
                if Int.random(in: 0...10) > 3 { // 70% chance of data
                    let mood = Int.random(in: 2...5)
                    moods[String(format: "2026-%02d-%02d", month, day)] = mood
                }
            }
        }

        return moods
    }
}
