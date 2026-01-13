import XCTest
@testable import MindFriendApp

final class APIEndpointTests: XCTestCase {

    // MARK: - Path Tests

    func testAuthEndpointPaths() {
        let appleRequest = AppleSignInRequest(
            identityToken: "token",
            authorizationCode: "code",
            fullName: nil,
            email: nil
        )
        let googleRequest = GoogleSignInRequest(
            idToken: "token",
            email: nil,
            fullName: nil
        )

        XCTAssertEqual(APIEndpoint.appleSignIn(appleRequest).path, "/v1/auth/apple")
        XCTAssertEqual(APIEndpoint.googleSignIn(googleRequest).path, "/v1/auth/google")
        XCTAssertEqual(APIEndpoint.logout.path, "/v1/auth/logout")
    }

    func testUserEndpointPaths() {
        XCTAssertEqual(APIEndpoint.getProfile.path, "/v1/me")
        XCTAssertEqual(APIEndpoint.deleteAccount.path, "/v1/me/delete")
        XCTAssertEqual(APIEndpoint.exportData.path, "/v1/me/export")
    }

    func testQuestEndpointPaths() {
        XCTAssertEqual(APIEndpoint.getTodayQuest.path, "/v1/quests/today")
        XCTAssertEqual(APIEndpoint.completeQuest(id: "123", reflectionNote: nil, rating: nil).path, "/v1/quests/123/complete")
        XCTAssertEqual(APIEndpoint.skipQuest(id: "456").path, "/v1/quests/456/skip")
    }

    func testCircleEndpointPaths() {
        XCTAssertEqual(APIEndpoint.getCircles.path, "/v1/circles")
        XCTAssertEqual(APIEndpoint.getCircle(id: "abc").path, "/v1/circles/abc")
        XCTAssertEqual(APIEndpoint.joinCircle(inviteCode: "XYZ123").path, "/v1/circles/join")
        XCTAssertEqual(APIEndpoint.leaveCircle(id: "abc").path, "/v1/circles/abc/leave")
    }

    // MARK: - HTTP Method Tests

    func testAuthEndpointMethods() {
        let appleRequest = AppleSignInRequest(
            identityToken: "token",
            authorizationCode: "code",
            fullName: nil,
            email: nil
        )

        XCTAssertEqual(APIEndpoint.appleSignIn(appleRequest).method, .post)
        XCTAssertEqual(APIEndpoint.logout.method, .post)
    }

    func testGetEndpointMethods() {
        XCTAssertEqual(APIEndpoint.getProfile.method, .get)
        XCTAssertEqual(APIEndpoint.getTodayQuest.method, .get)
        XCTAssertEqual(APIEndpoint.getCircles.method, .get)
        XCTAssertEqual(APIEndpoint.getConversations.method, .get)
    }

    func testPatchEndpointMethods() {
        XCTAssertEqual(APIEndpoint.updateProfile(displayName: "Test", timezone: nil).method, .patch)
    }

    // MARK: - Auth Required Tests

    func testPublicEndpoints() {
        let appleRequest = AppleSignInRequest(
            identityToken: "token",
            authorizationCode: "code",
            fullName: nil,
            email: nil
        )
        let googleRequest = GoogleSignInRequest(
            idToken: "token",
            email: nil,
            fullName: nil
        )

        XCTAssertFalse(APIEndpoint.appleSignIn(appleRequest).requiresAuth)
        XCTAssertFalse(APIEndpoint.googleSignIn(googleRequest).requiresAuth)
        XCTAssertFalse(APIEndpoint.getCrisisResources(country: nil).requiresAuth)
    }

    func testProtectedEndpoints() {
        XCTAssertTrue(APIEndpoint.getProfile.requiresAuth)
        XCTAssertTrue(APIEndpoint.getTodayQuest.requiresAuth)
        XCTAssertTrue(APIEndpoint.getCircles.requiresAuth)
        XCTAssertTrue(APIEndpoint.deleteAccount.requiresAuth)
    }

    // MARK: - Query Items Tests

    func testMoodsQueryItems() {
        let endpoint = APIEndpoint.getMoods(from: "2024-01-01", to: "2024-01-31")
        let queryItems = endpoint.queryItems

        XCTAssertNotNil(queryItems)
        XCTAssertEqual(queryItems?.count, 2)
        XCTAssertTrue(queryItems!.contains { $0.name == "from" && $0.value == "2024-01-01" })
        XCTAssertTrue(queryItems!.contains { $0.name == "to" && $0.value == "2024-01-31" })
    }

    func testMessagesQueryItems() {
        let endpoint = APIEndpoint.getMessages(conversationId: "conv-1", limit: 50)
        let queryItems = endpoint.queryItems

        XCTAssertNotNil(queryItems)
        XCTAssertEqual(queryItems?.count, 1)
        XCTAssertEqual(queryItems?.first?.name, "limit")
        XCTAssertEqual(queryItems?.first?.value, "50")
    }

    func testExercisesQueryItems() {
        let withType = APIEndpoint.getExercises(type: .breathing)
        let withoutType = APIEndpoint.getExercises(type: nil)

        XCTAssertNotNil(withType.queryItems)
        XCTAssertEqual(withType.queryItems?.first?.value, "breathing")

        XCTAssertNil(withoutType.queryItems)
    }

    // MARK: - Request Body Tests

    func testAppleSignInRequestBody() {
        let request = AppleSignInRequest(
            identityToken: "id-token",
            authorizationCode: "auth-code",
            fullName: "John Doe",
            email: "john@example.com"
        )
        let endpoint = APIEndpoint.appleSignIn(request)

        XCTAssertNotNil(endpoint.body)
    }

    func testCompleteQuestRequestBody() {
        let endpoint = APIEndpoint.completeQuest(
            id: "quest-1",
            reflectionNote: "Great experience!",
            rating: 5
        )

        XCTAssertNotNil(endpoint.body)
    }

    func testNoBodyForGetEndpoints() {
        XCTAssertNil(APIEndpoint.getProfile.body)
        XCTAssertNil(APIEndpoint.getTodayQuest.body)
        XCTAssertNil(APIEndpoint.getCircles.body)
    }
}
