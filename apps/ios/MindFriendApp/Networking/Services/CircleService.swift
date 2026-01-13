import Foundation

/// Service for friend circles
final class CircleService: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getCircles() async throws -> [FriendCircle] {
        try await apiClient.request(.getCircles)
    }

    func createCircle(name: String, description: String?) async throws -> FriendCircle {
        try await apiClient.request(.createCircle(name: name, description: description))
    }

    func joinCircle(inviteCode: String) async throws -> FriendCircle {
        try await apiClient.request(.joinCircle(inviteCode: inviteCode))
    }

    func getCircle(id: String) async throws -> CircleDetail {
        try await apiClient.request(.getCircle(id: id))
    }

    func getFeed(circleId: String, from: String, to: String) async throws -> [CirclePost] {
        try await apiClient.request(.getCircleFeed(id: circleId, from: from, to: to))
    }

    func postCheckin(circleId: String, moodEmoji: String, bodyText: String?) async throws -> CirclePost {
        try await apiClient.request(.postCheckin(circleId: circleId, moodEmoji: moodEmoji, bodyText: bodyText))
    }

    func leaveCircle(id: String) async throws {
        try await apiClient.requestVoid(.leaveCircle(id: id))
    }
}

struct CircleDetail: Decodable {
    let circle: FriendCircle
    let members: [CircleMember]
}
