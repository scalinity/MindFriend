import Foundation
@testable import MindFriendApp

/// Mock Supabase client for testing
struct MockSupabaseClient {
    func from(_ table: String) -> MockPostgrestQueryBuilder {
        MockPostgrestQueryBuilder()
    }

    var auth: MockSupabaseAuth {
        MockSupabaseAuth()
    }
}

/// Mock Postgrest query builder
struct MockPostgrestQueryBuilder {
    func select(_ columns: String = "*") -> MockPostgrestQueryBuilder {
        return self
    }
    
    func eq(_ column: String, _ value: Any) -> MockPostgrestQueryBuilder {
        return self
    }
    
    func execute() async throws -> MockPostgrestResponse {
        MockPostgrestResponse()
    }
}

/// Mock Postgrest response
struct MockPostgrestResponse {
    var value: Any = []
}

/// Mock Supabase Auth
struct MockSupabaseAuth {}
