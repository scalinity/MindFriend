import Foundation
import Supabase
import OSLog

@MainActor
final class ActionPlanService {
    private let authService: SupabaseAuthService
    private let supabase: SupabaseClient

    init(authService: SupabaseAuthService, supabase: SupabaseClient) {
        self.authService = authService
        self.supabase = supabase
    }

    private struct ActionPlanRow: Codable {
        let id: UUID
        let userId: UUID
        let sourceType: ActionPlanSourceType
        let planSize: ActionPlanSize
        let localDate: String
        let timezone: String
        let status: ActionPlanStatus
        let scheduledFor: Date?
        let createdAt: Date
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case sourceType = "source_type"
            case planSize = "plan_size"
            case localDate = "local_date"
            case timezone
            case status
            case scheduledFor = "scheduled_for"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        func toModel() -> ActionPlan {
            ActionPlan(
                id: id.uuidString,
                userId: userId.uuidString,
                sourceType: sourceType,
                planSize: planSize,
                localDate: localDate,
                timezone: timezone,
                status: status,
                scheduledFor: scheduledFor,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private struct ActionPlanItemRow: Codable {
        let id: UUID
        let planId: UUID
        let itemType: ActionPlanItemType
        let referenceId: UUID?
        let title: String
        let durationMinutes: Int
        let sortOrder: Int
        let itemStatus: ActionPlanItemStatus
        let completedAt: Date?
        let skippedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case planId = "plan_id"
            case itemType = "item_type"
            case referenceId = "reference_id"
            case title
            case durationMinutes = "duration_minutes"
            case sortOrder = "sort_order"
            case itemStatus = "item_status"
            case completedAt = "completed_at"
            case skippedAt = "skipped_at"
        }

        func toModel(planId: String) -> ActionPlanItem {
            ActionPlanItem(
                id: id.uuidString,
                planId: planId,
                itemType: itemType,
                referenceId: referenceId?.uuidString,
                title: title,
                durationMinutes: durationMinutes,
                sortOrder: sortOrder,
                status: itemStatus,
                completedAt: completedAt,
                skippedAt: skippedAt
            )
        }
    }

    private static func localDateString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        return formatter.string(from: Date())
    }


    private var userId: UUID {
        get throws {
            guard let id = authService.userId else {
                throw DataError.notAuthenticated
            }
            return id
        }
    }

    func fetchLatestPlan(timezone: String) async throws -> (ActionPlan, [ActionPlanItem])? {
        let localDate = Self.localDateString(timezone: timezone)
        let planRows: [ActionPlanRow] = try await supabase
            .from(Tables.actionPlans)
            .select()
            .eq("user_id", value: try userId)
            .eq("local_date", value: localDate)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let planRow = planRows.first else { return nil }

        let itemRows: [ActionPlanItemRow] = try await supabase
            .from(Tables.actionPlanItems)
            .select()
            .eq("plan_id", value: planRow.id)
            .order("sort_order", ascending: true)
            .execute()
            .value

        let plan = planRow.toModel()
        let items = itemRows.map { $0.toModel(planId: plan.id) }
        return (plan, items)
    }

    func generatePlan(
        sourceType: ActionPlanSourceType,
        planSize: ActionPlanSize,
        timezone: String,
        regenerate: Bool
    ) async throws -> (ActionPlan, [ActionPlanItem], Int?) {
        _ = try userId

        let request: [String: AnyEncodable] = [
            "sourceType": AnyEncodable(sourceType.rawValue),
            "planSize": AnyEncodable(planSize.rawValue),
            "timezone": AnyEncodable(timezone),
            "regenerate": AnyEncodable(regenerate)
        ]

        struct Response: Codable {
            let planId: String
            let planStatus: String
            let items: [ActionPlanItemResponse]
            let usedFallback: Bool?
            let quotaRemaining: Int?
        }

        struct ActionPlanItemResponse: Codable {
            let id: String
            let itemType: ActionPlanItemType
            let referenceId: String?
            let title: String
            let durationMinutes: Int
            let sortOrder: Int
            let itemStatus: ActionPlanItemStatus
        }

        let response: Response
        do {
            let rawData: Data = try await supabase.functions.invoke(
                "generate-action-plan",
                options: .init(body: request)
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            response = try decoder.decode(Response.self, from: rawData)
        } catch let error as FunctionsError {
            switch error {
            case .httpError(let code, let data):
                let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
                Log.data.error("[ActionPlan] Generate plan error \(code): \(responseBody)")
                if code == 429 || responseBody.lowercased().contains("quota") {
                    throw APIError.quotaExceeded
                }
                throw APIError.serverError("Server error (\(code)): \(responseBody)")
            case .relayError:
                throw APIError.networkError("Unable to reach server")
            }
        }

        let localDate = Self.localDateString(timezone: timezone)
        let plan = ActionPlan(
            id: response.planId,
            userId: authService.userId ?? "",
            sourceType: sourceType,
            planSize: planSize,
            localDate: localDate,
            timezone: timezone,
            status: ActionPlanStatus(rawValue: response.planStatus) ?? .draft,
            scheduledFor: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let items = response.items.map { item in
            ActionPlanItem(
                id: item.id,
                planId: response.planId,
                itemType: item.itemType,
                referenceId: item.referenceId,
                title: item.title,
                durationMinutes: item.durationMinutes,
                sortOrder: item.sortOrder,
                status: item.itemStatus,
                completedAt: nil,
                skippedAt: nil
            )
        }
        .sorted { $0.sortOrder < $1.sortOrder }

        return (plan, items, response.quotaRemaining)
    }

    struct ActionPlanItemUpdate: Equatable {
        let id: String
        let itemType: ActionPlanItemType?
        let referenceId: String?
        let title: String?
        let durationMinutes: Int?
        let sortOrder: Int?
    }

    func recordPlan(
        planId: String,
        status: ActionPlanStatus?,
        scheduledFor: Date?,
        itemsCompleted: [String],
        itemsSkipped: [String],
        feedback: ActionPlanFeedback?,
        items: [ActionPlanItemUpdate] = [],
        removeItemIds: [String] = []
    ) async throws -> (ActionPlan, [ActionPlanItem]) {
        let itemPayloads: [[String: AnyEncodable]] = items.map { item in
            [
                "id": AnyEncodable(item.id),
                "itemType": AnyEncodable(item.itemType?.rawValue),
                "referenceId": AnyEncodable(item.referenceId),
                "title": AnyEncodable(item.title),
                "durationMinutes": AnyEncodable(item.durationMinutes),
                "sortOrder": AnyEncodable(item.sortOrder)
            ]
        }

        let request: [String: AnyEncodable] = [
            "planId": AnyEncodable(planId),
            "status": AnyEncodable(status?.rawValue),
            "scheduledFor": AnyEncodable(scheduledFor?.iso8601String),
            "itemsCompleted": AnyEncodable(itemsCompleted),
            "itemsSkipped": AnyEncodable(itemsSkipped),
            "items": AnyEncodable(itemPayloads.isEmpty ? nil : itemPayloads),
            "removeItemIds": AnyEncodable(removeItemIds.isEmpty ? nil : removeItemIds),
            "feedback": AnyEncodable(feedback == nil ? nil : [
                "rating": AnyEncodable(feedback?.rating ?? nil as Int?),
                "notes": AnyEncodable(feedback?.notes ?? nil as String?)
            ])
        ]

        struct Response: Codable {
            let plan: ActionPlanResponse
            let items: [ActionPlanItemResponse]
        }

        struct ActionPlanResponse: Codable {
            let id: String
            let status: ActionPlanStatus
            let sourceType: ActionPlanSourceType
            let planSize: ActionPlanSize
            let localDate: String
            let timezone: String
            let scheduledFor: Date?
        }

        struct ActionPlanItemResponse: Codable {
            let id: String
            let itemType: ActionPlanItemType
            let referenceId: String?
            let title: String
            let durationMinutes: Int
            let sortOrder: Int
            let itemStatus: ActionPlanItemStatus
            let completedAt: Date?
            let skippedAt: Date?
        }

        let response: Response
        do {
            let rawData: Data = try await supabase.functions.invoke(
                "record-action-plan",
                options: .init(body: request)
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            response = try decoder.decode(Response.self, from: rawData)
        } catch let error as FunctionsError {
            switch error {
            case .httpError(let code, let data):
                let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
                Log.data.error("[ActionPlan] Record plan error \(code): \(responseBody)")
                throw APIError.serverError("Server error (\(code)): \(responseBody)")
            case .relayError:
                throw APIError.networkError("Unable to reach server")
            }
        }

        let plan = ActionPlan(
            id: response.plan.id,
            userId: authService.userId ?? "",
            sourceType: response.plan.sourceType,
            planSize: response.plan.planSize,
            localDate: response.plan.localDate,
            timezone: response.plan.timezone,
            status: response.plan.status,
            scheduledFor: response.plan.scheduledFor,
            createdAt: Date(),
            updatedAt: Date()
        )

        let items = response.items.map { item in
            ActionPlanItem(
                id: item.id,
                planId: plan.id,
                itemType: item.itemType,
                referenceId: item.referenceId,
                title: item.title,
                durationMinutes: item.durationMinutes,
                sortOrder: item.sortOrder,
                status: item.itemStatus,
                completedAt: item.completedAt,
                skippedAt: item.skippedAt
            )
        }
        .sorted { $0.sortOrder < $1.sortOrder }

        return (plan, items)
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
