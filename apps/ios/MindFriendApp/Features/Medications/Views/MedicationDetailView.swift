import SwiftUI

struct MedicationDetailView: View {
    let medication: Medication
    @State private var adherenceStats: MedicationAdherenceStats?
    @State private var logs: [MedicationLog] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: medication.icon.systemImage)
                        .font(.system(size: 32))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication.name)
                            .font(.headline)

                        if let dosage = medication.dosage {
                            Text(dosage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))

                // Adherence Section
                if let stats = adherenceStats {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adherence This Month")
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stats.displayPercentage)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text("\(stats.takenCount)/\(stats.totalScheduled) doses taken")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Streak")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(stats.streakDays) days")
                                    .font(.headline)
                            }
                        }

                        ProgressView(value: stats.percentage)
                            .tint(.green)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }

                // Recent Activity Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.headline)

                    if logs.isEmpty {
                        Text("No activity yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(logs.prefix(7)) { log in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.scheduledAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(log.status.rawValue.capitalized)
                                        .font(.caption)
                                }

                                Spacer()

                                Image(systemName: statusIcon(log.status))
                                    .foregroundColor(statusColor(log.status))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            // TODO: Load adherence stats and logs
            isLoading = false
        }
    }

    private func statusIcon(_ status: MedicationStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .late: return "clock.fill"
        case .pending: return "circle"
        }
    }

    private func statusColor(_ status: MedicationStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .red
        case .late: return .orange
        case .pending: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        MedicationDetailView(
            medication: Medication(
                id: UUID(),
                userId: UUID(),
                name: "Sertraline",
                dosage: "50mg",
                purpose: "Anxiety",
                color: nil,
                icon: .pill,
                frequency: .twiceDaily,
                timesPerDay: 2,
                scheduledTimes: [Date()],
                daysOfWeek: nil,
                reminderEnabled: true,
                reminderSound: "default",
                notificationText: nil,
                useGenericNotification: false,
                supplyCount: nil,
                refillReminderCount: nil,
                isActive: true,
                archivedAt: nil,
                startedAt: Date(),
                endedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
