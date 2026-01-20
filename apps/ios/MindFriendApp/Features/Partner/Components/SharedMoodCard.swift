import SwiftUI

/// Card displaying partner's recent moods
struct SharedMoodCard: View {
    let moods: [MoodEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.tint)
                Text("Their Mood")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if moods.isEmpty {
                Text("No mood data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    ForEach(moods.prefix(7), id: \.id) { mood in
                        VStack(spacing: 4) {
                            Text(moodEmoji(for: mood.moodScore))
                                .font(.title2)

                            Text(dayLabel(for: mood.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func moodEmoji(for value: Int) -> String {
        switch value {
        case 1: return "😢"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yest"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SharedMoodCard(moods: [
            MoodEntry(id: "1", localDate: "2026-01-20", moodScore: 5, anxietyScore: nil, energyScore: nil, note: nil, source: .manual, createdAt: Date()),
            MoodEntry(id: "2", localDate: "2026-01-19", moodScore: 4, anxietyScore: nil, energyScore: nil, note: nil, source: .manual, createdAt: Date().addingTimeInterval(-86400)),
            MoodEntry(id: "3", localDate: "2026-01-18", moodScore: 3, anxietyScore: nil, energyScore: nil, note: nil, source: .manual, createdAt: Date().addingTimeInterval(-172800))
        ])

        SharedMoodCard(moods: [])
    }
    .padding()
}
