import SwiftUI

struct MedicationDetailView: View {
    @EnvironmentObject private var container: DependencyContainer
    let medication: Medication
    @State private var adherenceStats: MedicationAdherenceStats?
    @State private var logs: [MedicationLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            isLoading = true
            defer { isLoading = false }

            do {
                // Load adherence stats
                struct DBMedicationStats: Decodable {
                    let medication_id: String
                    let taken_count: Int
                    let missed_count: Int
                    let late_count: Int
                    let total_scheduled: Int
                    let streak_days: Int
                }

                let stats: [DBMedicationStats] = try await container.supabase
                    .from("medication_adherence_stats")
                    .select()
                    .eq("medication_id", value: medication.id.uuidString)
                    .execute()
                    .value

                if let stat = stats.first {
                    let percentage = stat.total_scheduled > 0
                        ? Double(stat.taken_count) / Double(stat.total_scheduled)
                        : 0.0
                    adherenceStats = MedicationAdherenceStats(
                        percentage: percentage,
                        takenCount: stat.taken_count,
                        missedCount: stat.missed_count,
                        lateCount: stat.late_count,
                        totalScheduled: stat.total_scheduled,
                        streakDays: stat.streak_days
                    )
                }

                // Load recent logs
                struct DBMedicationLog: Decodable {
                    let id: String
                    let user_id: String
                    let medication_id: String
                    let scheduled_at: Date
                    let status: String
                    let logged_at: Date?
                    let skip_reason: String?
                    let notes: String?
                    let side_effects: [String]?
                    let mood_at_time: Int?
                    let created_at: Date
                }

                let dbLogs: [DBMedicationLog] = try await container.supabase
                    .from("medication_logs")
                    .select()
                    .eq("medication_id", value: medication.id.uuidString)
                    .order("scheduled_at", ascending: false)
                    .limit(30)
                    .execute()
                    .value

                logs = dbLogs.compactMap { log in
                    guard let status = MedicationStatus(rawValue: log.status),
                          let id = UUID(uuidString: log.id),
                          let userId = UUID(uuidString: log.user_id),
                          let medicationId = UUID(uuidString: log.medication_id) else {
                        return nil
                    }
                    return MedicationLog(
                        id: id,
                        userId: userId,
                        medicationId: medicationId,
                        scheduledAt: log.scheduled_at,
                        status: status,
                        loggedAt: log.logged_at,
                        skipReason: log.skip_reason,
                        notes: log.notes,
                        sideEffects: log.side_effects,
                        moodAtTime: log.mood_at_time,
                        createdAt: log.created_at
                    )
                }
            } catch {
                errorMessage = "Failed to load medication data"
            }
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
