import XCTest
@testable import MindFriendApp

final class AuthUITestIsolationTests: XCTestCase {
    func testAuthStorageIsUniqueToEachFixture() {
        let first = AuthUITestStorage()
        let second = AuthUITestStorage()
        let value = Data("synthetic-session".utf8)

        first.store(key: "session", value: value)
        XCTAssertEqual(first.retrieve(key: "session"), value)
        XCTAssertNil(second.retrieve(key: "session"))

        second.store(key: "session", value: value)
        first.remove(key: "session")
        XCTAssertNil(first.retrieve(key: "session"))
        XCTAssertEqual(second.retrieve(key: "session"), value)
    }

    func testFixtureStartsWithoutAnAuthSession() {
        let client = AuthUITestBackend.makeClient()
        XCTAssertNil(client.auth.currentSession)
    }

    func testFixtureDatabaseRequestIsRejectedByControlledTransport() async {
        let client = AuthUITestBackend.makeClient()
        do {
            _ = try await client.from("profiles").select().execute()
            XCTFail("The authentication fixture must never reach a backend")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Expected the fixture transport rejection, received \(error)")
        }
    }
}
