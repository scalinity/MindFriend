import XCTest

extension XCTestCase {
    /// Safely converts a JSON string to Data for testing.
    /// Fails the test if conversion fails, rather than crashing with force-unwrap.
    func jsonData(from jsonString: String, file: StaticString = #file, line: UInt = #line) -> Data {
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data", file: file, line: line)
            return Data()
        }
        return data
    }
}
