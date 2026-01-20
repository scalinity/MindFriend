import Foundation

struct AdherenceStats {
    let percentage: Double
    let takenCount: Int
    let missedCount: Int
    let lateCount: Int
    let totalScheduled: Int
    let streakDays: Int

    var displayPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }
}

final class AdherenceCalculator {
    func calculate(logs: [MedicationLog], totalScheduled: Int) -> AdherenceStats {
        let taken = logs.filter { $0.status == .taken }.count
        let late = logs.filter { $0.status == .late }.count
        let skipped = logs.filter { $0.status == .skipped }.count
        let pending = logs.filter { $0.status == .pending }.count

        let adherent = taken + late
        let percentage = totalScheduled > 0
            ? Double(adherent) / Double(totalScheduled)
            : 1.0

        let streak = calculateStreak(logs: logs.sorted { $0.scheduledAt > $1.scheduledAt })

        return AdherenceStats(
            percentage: percentage,
            takenCount: taken,
            missedCount: skipped + pending,
            lateCount: late,
            totalScheduled: totalScheduled,
            streakDays: streak
        )
    }

    func calculateMoodCorrelation(
        medicationLogs: [MedicationLog],
        moodLogs: [Mood]
    ) -> MedicationMoodCorrelation {
        var adherentDayMoods: [Double] = []
        var nonAdherentDayMoods: [Double] = []

        let calendar = Calendar.current
        let dateSet = Set(medicationLogs.map { calendar.startOfDay(for: $0.scheduledAt) })

        for day in dateSet {
            let dayLogs = medicationLogs.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
            let dayMoods = moodLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }

            guard !dayMoods.isEmpty else { continue }

            let avgMood = dayMoods.map { Double($0.score) }.reduce(0, +) / Double(dayMoods.count)
            let isAdherent = dayLogs.allSatisfy { $0.status == .taken || $0.status == .late }

            if isAdherent {
                adherentDayMoods.append(avgMood)
            } else {
                nonAdherentDayMoods.append(avgMood)
            }
        }

        let avgAdherent = adherentDayMoods.isEmpty
            ? 0
            : adherentDayMoods.reduce(0, +) / Double(adherentDayMoods.count)

        let avgNonAdherent = nonAdherentDayMoods.isEmpty
            ? 0
            : nonAdherentDayMoods.reduce(0, +) / Double(nonAdherentDayMoods.count)

        return MedicationMoodCorrelation(
            averageMoodWhenAdherent: avgAdherent,
            averageMoodWhenNotAdherent: avgNonAdherent,
            adherentDays: adherentDayMoods.count,
            nonAdherentDays: nonAdherentDayMoods.count
        )
    }

    private func calculateStreak(logs: [MedicationLog]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())

        for log in logs {
            let logDate = calendar.startOfDay(for: log.scheduledAt)

            if logDate == currentDate {
                if log.status == .taken || log.status == .late {
                    streak += 1
                }
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? Date()
            } else if logDate < currentDate {
                break
            }
        }

        return streak
    }
}
