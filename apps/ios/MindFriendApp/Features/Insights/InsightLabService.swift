// InsightLabService.swift
// Service for managing insight experiments via Supabase Edge Functions

import Foundation
import Supabase

@MainActor
final class InsightLabService: ObservableObject {
    private let supabase: SupabaseClient

    @Published private(set) var activeExperiment: InsightExperiment?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // JSON decoder configured for ISO8601 dates
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try with fractional seconds first
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try date-only format
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Fetch Active Experiment

    func fetchActiveExperiment() async {
        print("[InsightLabService] fetchActiveExperiment called, current activeExperiment: \(activeExperiment?.title ?? "nil")")
        isLoading = true
        error = nil

        do {
            guard let userId = supabase.auth.currentUser?.id else {
                print("[InsightLabService] fetchActiveExperiment - No user ID, setting activeExperiment to nil")
                activeExperiment = nil
                isLoading = false
                return
            }

            // Query active experiment
            let experiments: [InsightExperimentRow] = try await supabase
                .from("insight_experiments")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .limit(1)
                .execute()
                .value

            print("[InsightLabService] fetchActiveExperiment - Found \(experiments.count) experiments")

            guard let experimentRow = experiments.first else {
                print("[InsightLabService] fetchActiveExperiment - No active experiment found, setting to nil")
                activeExperiment = nil
                isLoading = false
                return
            }

            // Fetch days for this experiment
            let days: [ExperimentDayRow] = try await supabase
                .from("insight_experiment_days")
                .select("*")
                .eq("experiment_id", value: experimentRow.id.uuidString)
                .order("day_index")
                .execute()
                .value

            // Convert to model
            activeExperiment = InsightExperiment(
                id: experimentRow.id,
                title: experimentRow.title,
                description: experimentRow.description,
                actionType: experimentRow.actionType,
                startedAt: experimentRow.startedAt,
                endedAt: experimentRow.endedAt,
                status: ExperimentStatus(rawValue: experimentRow.status) ?? .active,
                baselineMoodAvg: experimentRow.baselineMoodAvg,
                baselineEnergyAvg: experimentRow.baselineEnergyAvg,
                days: days.map { row in
                    ExperimentDay(
                        dayIndex: row.dayIndex,
                        completed: row.completed,
                        completedAt: row.completedAt,
                        moodScore: row.moodScore,
                        energyScore: row.energyScore
                    )
                }
            )
        } catch {
            self.error = "Failed to fetch experiment: \(error.localizedDescription)"
            print("InsightLabService.fetchActiveExperiment error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Start Experiment

    func startExperiment(actionType: ExperimentActionType) async throws -> InsightExperiment {
        isLoading = true
        error = nil

        defer { isLoading = false }

        print("[InsightLabService] Starting experiment: \(actionType.rawValue)")

        let request = StartExperimentRequest(
            actionType: actionType.rawValue,
            title: actionType.title,
            description: actionType.description
        )

        let startResponse: StartExperimentResponse = try await supabase.functions.invoke(
            "start-insight-experiment",
            options: FunctionInvokeOptions(body: request)
        )

        print("[InsightLabService] Received response - experimentId: \(startResponse.experimentId), title: \(startResponse.title), days: \(startResponse.days.count)")

        let experiment = InsightExperiment(
            id: startResponse.experimentId,
            title: startResponse.title,
            description: startResponse.description,
            actionType: startResponse.actionType,
            startedAt: startResponse.startedAt,
            endedAt: nil,
            status: startResponse.status,
            baselineMoodAvg: startResponse.baselineMoodAvg,
            baselineEnergyAvg: startResponse.baselineEnergyAvg,
            days: startResponse.days
        )

        print("[InsightLabService] Setting activeExperiment to: \(experiment.title)")
        activeExperiment = experiment
        print("[InsightLabService] activeExperiment is now: \(activeExperiment?.title ?? "nil")")
        return experiment
    }

    // MARK: - Record Day

    func recordDay(experimentId: UUID, dayIndex: Int, moodScore: Int?, energyScore: Int?) async throws -> RecordDayResponse {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let request = RecordDayRequest(
            experimentId: experimentId,
            dayIndex: dayIndex,
            moodScore: moodScore,
            energyScore: energyScore
        )

        let recordResponse: RecordDayResponse = try await supabase.functions.invoke(
            "record-experiment-day",
            options: FunctionInvokeOptions(body: request)
        )

        // Update local state
        if var experiment = activeExperiment, experiment.id == experimentId {
            if let dayIdx = experiment.days.firstIndex(where: { $0.dayIndex == dayIndex }) {
                experiment.days[dayIdx].completed = true
                experiment.days[dayIdx].completedAt = recordResponse.completedAt
                experiment.days[dayIdx].moodScore = moodScore
                experiment.days[dayIdx].energyScore = energyScore
            }

            if recordResponse.experimentStatus == .completed {
                experiment.status = .completed
                experiment.endedAt = Date()
            }

            activeExperiment = experiment
        }

        return recordResponse
    }

    // MARK: - Generate Report

    func generateReport(experimentId: UUID) async throws -> ExperimentReport {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let request = GenerateReportRequest(experimentId: experimentId)

        return try await supabase.functions.invoke(
            "generate-experiment-report",
            options: FunctionInvokeOptions(body: request)
        )
    }

    // MARK: - Cancel Experiment

    func cancelExperiment(experimentId: UUID) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        try await supabase
            .from("insight_experiments")
            .update(["status": "cancelled", "ended_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: experimentId.uuidString)
            .execute()

        if activeExperiment?.id == experimentId {
            activeExperiment = nil
        }
    }

    // MARK: - Fetch Completed Experiments

    func fetchCompletedExperiments() async throws -> [InsightExperiment] {
        guard let userId = supabase.auth.currentUser?.id else {
            return []
        }

        let experiments: [InsightExperimentRow] = try await supabase
            .from("insight_experiments")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "completed")
            .order("ended_at", ascending: false)
            .limit(10)
            .execute()
            .value

        return experiments.map { row in
            InsightExperiment(
                id: row.id,
                title: row.title,
                description: row.description,
                actionType: row.actionType,
                startedAt: row.startedAt,
                endedAt: row.endedAt,
                status: ExperimentStatus(rawValue: row.status) ?? .completed,
                baselineMoodAvg: row.baselineMoodAvg,
                baselineEnergyAvg: row.baselineEnergyAvg,
                days: []
            )
        }
    }
}

// MARK: - Database Row Models

private struct InsightExperimentRow: Codable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String
    let actionType: String
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let baselineMoodAvg: Double?
    let baselineEnergyAvg: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case actionType = "action_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case baselineMoodAvg = "baseline_mood_avg"
        case baselineEnergyAvg = "baseline_energy_avg"
    }
}

private struct ExperimentDayRow: Codable {
    let id: UUID
    let experimentId: UUID
    let dayIndex: Int
    let completed: Bool
    let completedAt: Date?
    let moodScore: Int?
    let energyScore: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case experimentId = "experiment_id"
        case dayIndex = "day_index"
        case completed
        case completedAt = "completed_at"
        case moodScore = "mood_score"
        case energyScore = "energy_score"
    }
}
