import Foundation
import Supabase
import os.log

protocol ActionCardServiceProtocol {
    func generateActionCards(_ request: GenerateActionCardsRequest) async throws -> GenerateActionCardsResponse
    func recordActionTaken(_ request: CardActionRequest) async throws
    func dismissCard(_ request: DismissCardRequest) async throws
}

@MainActor
final class ActionCardService: ActionCardServiceProtocol {
    private let supabase: SupabaseClient
    private let logger = Logger(subsystem: "com.mindfriend.ios", category: "ActionCard")

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func generateActionCards(_ request: GenerateActionCardsRequest) async throws -> GenerateActionCardsResponse {
        let result: GenerateActionCardsResponse = try await supabase.functions.invoke(
            "generate-action-cards",
            options: FunctionInvokeOptions(body: request)
        )

        return result
    }

    func recordActionTaken(_ request: CardActionRequest) async throws {
        _ = try await supabase.functions.invoke(
            "card-action-taken",
            options: FunctionInvokeOptions(body: request)
        )
    }

    func dismissCard(_ request: DismissCardRequest) async throws {
        _ = try await supabase.functions.invoke(
            "dismiss-card",
            options: FunctionInvokeOptions(body: request)
        )
    }
}

struct EmptyResponse: Decodable {}
