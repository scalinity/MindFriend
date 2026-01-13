import Foundation

/// Service for user profile and settings
final class UserService: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getProfile() async throws -> UserProfile {
        try await apiClient.request(.getProfile)
    }

    func updateProfile(displayName: String?, timezone: String?) async throws -> UserProfile {
        try await apiClient.request(.updateProfile(displayName: displayName, timezone: timezone))
    }

    func updateSettings(_ settings: UserSettings) async throws {
        try await apiClient.requestVoid(.updateSettings(settings))
    }

    func registerDevice(apnsToken: String, deviceModel: String, osVersion: String) async throws -> DeviceResponse {
        try await apiClient.request(.registerDevice(
            apnsToken: apnsToken,
            deviceModel: deviceModel,
            osVersion: osVersion
        ))
    }

    func deleteAccount() async throws {
        try await apiClient.requestVoid(.deleteAccount)
    }

    func exportData() async throws -> UserDataExport {
        try await apiClient.request(.exportData)
    }
}

struct DeviceResponse: Decodable {
    let deviceId: String
}

struct UserDataExport: Decodable {
    let exportedAt: String
    let user: UserExportData

    struct UserExportData: Decodable {
        let id: String
        let handle: String
        let displayName: String
        let email: String?
    }
}
