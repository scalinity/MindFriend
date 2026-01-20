import Foundation
import Supabase
import Realtime

/// Service for managing circle rituals
@MainActor
final class RitualService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var currentRitual: CircleRitual?
    @Published var attendees: [RitualAttendeeInfo] = []
    @Published var reflections: [RitualReflectionInfo] = []

    private var realtimeChannel: RealtimeChannelV2?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Request Structs

    private struct CreateRitualRequest: Codable {
        let circleId: String
        let title: String
        let ritualType: String
        let startOption: String
        let scheduledFor: String?
    }

    private struct JoinRitualRequest: Codable {
        let ritualId: String
    }

    private struct CompleteRitualRequest: Codable {
        let ritualId: String
    }

    private struct AddReflectionRequest: Codable {
        let ritualId: String
        let content: String
    }

    // MARK: - Ritual CRUD Operations

    /// Create a new ritual for a circle
    func createRitual(
        circleId: UUID,
        title: String,
        ritualType: RitualType,
        startNow: Bool,
        scheduledFor: Date? = nil
    ) async throws -> CircleRitual {
        let request = CreateRitualRequest(
            circleId: circleId.uuidString,
            title: title,
            ritualType: ritualType.rawValue,
            startOption: startNow ? "now" : "scheduled",
            scheduledFor: scheduledFor?.ISO8601Format()
        )

        let data: Data = try await supabase.functions.invoke(
            "create-circle-ritual",
            options: .init(body: request)
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let createResponse = try decoder.decode(CreateRitualResponse.self, from: data)
        return convertToCircleRitual(createResponse.ritual)
    }

    /// Join an active or starting ritual
    func joinRitual(ritualId: UUID) async throws -> (ritual: CircleRitual, currentStep: RitualStep?, attendees: [RitualAttendeeInfo]) {
        let request = JoinRitualRequest(ritualId: ritualId.uuidString)

        let data: Data = try await supabase.functions.invoke(
            "join-circle-ritual",
            options: .init(body: request)
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let joinResponse = try decoder.decode(JoinRitualResponse.self, from: data)

        let ritual = convertJoinResponseToRitual(joinResponse.ritual)
        let currentStep = joinResponse.currentStep.map { step in
            RitualStep(
                stepIndex: step.stepIndex,
                prompt: step.prompt,
                timeRemaining: step.timeRemaining,
                completed: step.completed
            )
        }
        let attendeeList = joinResponse.attendees.map { attendee in
            RitualAttendeeInfo(
                userId: attendee.userId,
                displayName: attendee.displayName,
                joinedAt: ISO8601DateFormatter().date(from: attendee.joinedAt) ?? Date()
            )
        }

        // Update local state
        self.currentRitual = ritual
        self.attendees = attendeeList

        return (ritual, currentStep, attendeeList)
    }

    /// Complete a ritual (creator only)
    func completeRitual(ritualId: UUID) async throws -> (attendeeCount: Int, recapPostId: UUID?) {
        let request = CompleteRitualRequest(ritualId: ritualId.uuidString)

        let data: Data = try await supabase.functions.invoke(
            "complete-circle-ritual",
            options: .init(body: request)
        )

        let decoder = JSONDecoder()
        let completeResponse = try decoder.decode(CompleteRitualResponse.self, from: data)

        return (completeResponse.ritual.attendeeCount, completeResponse.recapPostId)
    }

    /// Add a reflection after a ritual ends
    func addReflection(ritualId: UUID, content: String) async throws -> RitualReflection {
        let request = AddReflectionRequest(
            ritualId: ritualId.uuidString,
            content: content
        )

        let data: Data = try await supabase.functions.invoke(
            "add-ritual-reflection",
            options: .init(body: request)
        )

        let decoder = JSONDecoder()
        let addResponse = try decoder.decode(AddReflectionResponse.self, from: data)

        return RitualReflection(
            id: addResponse.reflection.id,
            ritualId: addResponse.reflection.ritualId,
            userId: addResponse.reflection.userId,
            content: addResponse.reflection.content,
            createdAt: ISO8601DateFormatter().date(from: addResponse.reflection.createdAt) ?? Date()
        )
    }

    // MARK: - Fetch Operations

    /// Fetch upcoming rituals for a circle
    func fetchUpcomingRituals(circleId: UUID) async throws -> [CircleRitual] {
        let now = Date()

        let response: [CircleRitual] = try await supabase
            .from("circle_rituals")
            .select()
            .eq("circle_id", value: circleId.uuidString)
            .in("status", values: ["scheduled", "active"])
            .gte("scheduled_for", value: now.addingTimeInterval(-2 * 60).ISO8601Format()) // Include grace period
            .order("scheduled_for")
            .execute()
            .value

        return response
    }

    /// Fetch ritual details
    func fetchRitual(ritualId: UUID) async throws -> CircleRitual {
        let response: CircleRitual = try await supabase
            .from("circle_rituals")
            .select()
            .eq("id", value: ritualId.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    /// Fetch attendees for a ritual
    func fetchAttendees(ritualId: UUID) async throws -> [RitualAttendeeInfo] {
        struct AttendeeWithProfile: Decodable {
            let userId: UUID
            let joinedAt: Date
            let profile: ProfileInfo?

            struct ProfileInfo: Decodable {
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                }
            }

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case joinedAt = "joined_at"
                case profile = "profiles"
            }
        }

        let response: [AttendeeWithProfile] = try await supabase
            .from("circle_ritual_attendees")
            .select("user_id, joined_at, profiles:user_id(display_name)")
            .eq("ritual_id", value: ritualId.uuidString)
            .is("left_at", value: nil)
            .execute()
            .value

        return response.map { attendee in
            RitualAttendeeInfo(
                userId: attendee.userId,
                displayName: attendee.profile?.displayName ?? "Unknown",
                joinedAt: attendee.joinedAt
            )
        }
    }

    /// Fetch reflections for a ritual
    func fetchReflections(ritualId: UUID) async throws -> [RitualReflectionInfo] {
        struct ReflectionWithProfile: Decodable {
            let id: UUID
            let userId: UUID
            let bodyText: String
            let createdAt: Date
            let profile: ProfileInfo?

            struct ProfileInfo: Decodable {
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                }
            }

            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case bodyText = "body_text"
                case createdAt = "created_at"
                case profile = "profiles"
            }
        }

        let response: [ReflectionWithProfile] = try await supabase
            .from("circle_ritual_reflections")
            .select("id, user_id, body_text, created_at, profiles:user_id(display_name)")
            .eq("ritual_id", value: ritualId.uuidString)
            .order("created_at")
            .execute()
            .value

        return response.map { reflection in
            RitualReflectionInfo(
                id: reflection.id,
                userId: reflection.userId,
                displayName: reflection.profile?.displayName ?? "Unknown",
                content: reflection.bodyText,
                createdAt: reflection.createdAt
            )
        }
    }

    // MARK: - Realtime Subscriptions

    /// Subscribe to ritual updates
    func subscribeToRitual(
        ritualId: UUID,
        onUserJoined: @escaping (RitualAttendeeInfo) -> Void,
        onUserLeft: @escaping (UUID) -> Void,
        onCompleted: @escaping (Int, UUID?) -> Void,
        onReflectionAdded: @escaping (RitualReflectionInfo) -> Void
    ) async {
        // Unsubscribe from previous channel if any
        await unsubscribeFromRitual()

        let channel = supabase.realtimeV2.channel("circle_ritual:\(ritualId.uuidString)")

        // Listen for user joined events
        let joinedStream = channel.broadcastStream(event: "user_joined")
        Task {
            for await message in joinedStream {
                await handleUserJoined(message, callback: onUserJoined)
            }
        }

        // Listen for user left events
        let leftStream = channel.broadcastStream(event: "user_left")
        Task {
            for await message in leftStream {
                await handleUserLeft(message, callback: onUserLeft)
            }
        }

        // Listen for completed events
        let completedStream = channel.broadcastStream(event: "completed")
        Task {
            for await message in completedStream {
                await handleCompleted(message, callback: onCompleted)
            }
        }

        // Listen for reflection added events
        let reflectionStream = channel.broadcastStream(event: "reflection_added")
        Task {
            for await message in reflectionStream {
                await handleReflectionAdded(message, callback: onReflectionAdded)
            }
        }

        await channel.subscribe()
        self.realtimeChannel = channel
    }

    /// Unsubscribe from ritual updates
    func unsubscribeFromRitual() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
            self.realtimeChannel = nil
        }
    }

    private func handleUserJoined(_ message: JSONObject, callback: @escaping (RitualAttendeeInfo) -> Void) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON,
              let userIdJSON = payload["userId"],
              case .string(let userIdString) = userIdJSON,
              let userId = UUID(uuidString: userIdString),
              let displayNameJSON = payload["displayName"],
              case .string(let displayName) = displayNameJSON else { return }

        var joinedAt = Date()
        if let joinedAtJSON = payload["joinedAt"],
           case .string(let joinedAtString) = joinedAtJSON {
            joinedAt = ISO8601DateFormatter().date(from: joinedAtString) ?? Date()
        }

        let attendee = RitualAttendeeInfo(userId: userId, displayName: displayName, joinedAt: joinedAt)
        await MainActor.run { callback(attendee) }
    }

    private func handleUserLeft(_ message: JSONObject, callback: @escaping (UUID) -> Void) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON,
              let userIdJSON = payload["userId"],
              case .string(let userIdString) = userIdJSON,
              let userId = UUID(uuidString: userIdString) else { return }

        await MainActor.run { callback(userId) }
    }

    private func handleCompleted(_ message: JSONObject, callback: @escaping (Int, UUID?) -> Void) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON else { return }

        var attendeeCount = 0
        if let countJSON = payload["attendeeCount"],
           case .integer(let count) = countJSON {
            attendeeCount = count
        }

        var recapPostId: UUID?
        if let recapIdJSON = payload["recapPostId"],
           case .string(let recapIdString) = recapIdJSON {
            recapPostId = UUID(uuidString: recapIdString)
        }

        await MainActor.run { callback(attendeeCount, recapPostId) }
    }

    private func handleReflectionAdded(_ message: JSONObject, callback: @escaping (RitualReflectionInfo) -> Void) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON,
              let reflectionIdJSON = payload["reflectionId"],
              case .string(let reflectionIdString) = reflectionIdJSON,
              let reflectionId = UUID(uuidString: reflectionIdString),
              let userIdJSON = payload["userId"],
              case .string(let userIdString) = userIdJSON,
              let userId = UUID(uuidString: userIdString),
              let displayNameJSON = payload["displayName"],
              case .string(let displayName) = displayNameJSON,
              let contentJSON = payload["content"],
              case .string(let content) = contentJSON else { return }

        var createdAt = Date()
        if let createdAtJSON = payload["createdAt"],
           case .string(let createdAtString) = createdAtJSON {
            createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        }

        let reflection = RitualReflectionInfo(
            id: reflectionId,
            userId: userId,
            displayName: displayName,
            content: content,
            createdAt: createdAt
        )
        await MainActor.run { callback(reflection) }
    }

    // MARK: - Helpers

    private func convertToCircleRitual(_ data: CreateRitualResponse.RitualData) -> CircleRitual {
        let formatter = ISO8601DateFormatter()
        return CircleRitual(
            id: data.id,
            circleId: data.circleId,
            createdBy: data.createdBy,
            title: data.title,
            ritualType: RitualType(rawValue: data.ritualType) ?? .gratitude,
            scheduledFor: formatter.date(from: data.scheduledFor) ?? Date(),
            durationSeconds: data.durationSeconds,
            status: RitualStatus(rawValue: data.status) ?? .scheduled,
            createdAt: formatter.date(from: data.createdAt) ?? Date(),
            completedAt: nil
        )
    }

    private func convertJoinResponseToRitual(_ data: JoinRitualResponse.RitualResponse) -> CircleRitual {
        let formatter = ISO8601DateFormatter()
        return CircleRitual(
            id: data.id,
            circleId: UUID(), // Not provided in join response
            createdBy: UUID(), // Not provided in join response
            title: data.title,
            ritualType: RitualType(rawValue: data.ritualType) ?? .gratitude,
            scheduledFor: formatter.date(from: data.scheduledFor) ?? Date(),
            durationSeconds: data.durationSeconds,
            status: RitualStatus(rawValue: data.status) ?? .active,
            createdAt: Date(),
            completedAt: nil
        )
    }
}
