import Foundation
import Supabase

protocol ActionCardServiceProtocol {
    func generateActionCards(_ request: GenerateActionCardsRequest) async throws -> GenerateActionCardsResponse
    func recordActionTaken(_ request: CardActionRequest) async throws
    func dismissCard(_ request: DismissCardRequest) async throws
}

@MainActor
final class ActionCardService: ActionCardServiceProtocol {
    private let supabase: SupabaseClient
    private let logger = Logger(subsystem: "ActionCardService", category: "chat")

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func generateActionCards(_ request: GenerateActionCardsRequest) async throws -> GenerateActionCardsResponse {
        return try await supabase.functions.invoke(
            "generate-action-cards",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }

    func recordActionTaken(_ request: CardActionRequest) async throws {
        let _: EmptyResponse = try await supabase.functions.invoke(
            "card-action-taken",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }

    func dismissCard(_ request: DismissCardRequest) async throws {
        let _: EmptyResponse = try await supabase.functions.invoke(
            "dismiss-card",
            options: .init(
                body: EncodableValue(request),
                headers: ["Content-Type": "application/json"]
            )
        ).value
    }
}

struct EmptyResponse: Decodable {}
