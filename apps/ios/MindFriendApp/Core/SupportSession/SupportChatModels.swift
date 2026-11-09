import Foundation

/// Local identity is checked around suspension; only its owner/session/scope/revision go on the wire.
struct SupportChatRequestContext: Equatable, Sendable {
    let owner: OfflineOwnerProof
    let sessionID: UUID
    let scope: SupportContextScope
    let privacyRevision: Int64
}

enum SupportMessageOrigin: String, Codable, Equatable, Sendable {
    case model
    case interfaceFallback = "interface_fallback"
    case safetyResponse = "safety_response"
}

struct SupportChatReceipt: Codable, Equatable, Identifiable, Sendable {
    struct Provider: Codable, Equatable, Sendable {
        let vendor: String
        let model: String
        let routeVersion: String
        enum CodingKeys: String, CodingKey { case vendor, model; case routeVersion = "route_version" }
    }
    struct Source: Codable, Equatable, Identifiable, Sendable {
        let kind: String
        let id: UUID
        let revision: Int64
        let date: String?
    }
    let schemaVersion: Int
    let receiptID: UUID
    var id: UUID { receiptID }
    let requestID: UUID
    let sessionID: UUID?
    let conversationID: UUID
    let assistantMessageID: UUID
    let privacyRevision: Int64
    let scope: SupportContextScope
    let provider: Provider
    let sources: [Source]
    let exclusions: [String]
    /// ISO8601 from the server; kept distinct from the legacy message's Unix timestamp decoding.
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", receiptID = "receipt_id", requestID = "request_id"
        case sessionID = "support_session_id", conversationID = "conversation_id", assistantMessageID = "assistant_message_id"
        case privacyRevision = "privacy_revision", scope, provider, sources, exclusions, createdAt = "created_at"
    }
}

struct SupportChatProposal: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let template: SupportActivityTemplateKey
    let reasonCode: String
    let basisKind: String?
    let basisRef: UUID?
    let suggestedStep: String?
    let status: String
    let expiresAt: String
    enum CodingKeys: String, CodingKey {
        case id, template = "template_key", reasonCode = "reason_code", basisKind = "basis_kind", basisRef = "basis_ref"
        case suggestedStep = "suggested_step", status, expiresAt = "expires_at"
    }
    var expiry: Date? { SupportChatTimestamp.date(expiresAt) }
    var reason: String {
        switch reasonCode {
        case "current_request": return "You asked for an option to try."
        case "approved_preference": return "Based on a saved preference included in this reply’s context."
        case "selected_intent": return "An option for the intention you selected."
        default: return "An option you can try."
        }
    }
}

struct SupportChatMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: UUID
    let sessionID: UUID?
    let conversationID: UUID
    let scope: SupportContextScope
    let privacyRevision: Int64?
    let contentOrigin: SupportMessageOrigin
    let status: String
    let suppressOrdinaryCards: Bool
    let confirmed: Bool
    let contextReceipt: SupportChatReceipt?
    let proposal: SupportChatProposal?
    let proposalDropped: String?
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", requestID = "request_id", sessionID = "support_session_id"
        case conversationID = "conversation_id", scope, privacyRevision = "privacy_revision", contentOrigin = "content_origin"
        case status, suppressOrdinaryCards = "suppress_ordinary_cards", confirmed, contextReceipt = "context_receipt"
        case proposal, proposalDropped = "proposal_dropped"
    }

    /// A card needs the server-confirmed message/receipt identities and the exact prepared request context.
    /// Fixed safety guidance may remain available with explicitly unavailable receipt details; it never has a card.
    func validates(context: SupportChatRequestContext, conversationID: UUID, requestID: UUID,
                   assistantID: String, isSafety: Bool) -> Bool {
        guard schemaVersion == 1, self.requestID == requestID, self.conversationID == conversationID,
              sessionID == context.sessionID,
              scope == context.scope || (scope == .conversationOnly && context.scope == .personalized) else { return false }
        if isSafety, contentOrigin == .safetyResponse, suppressOrdinaryCards, proposal == nil,
           contextReceipt == nil { return true }
        guard confirmed, let receipt = contextReceipt, receipt.schemaVersion == 1,
              receipt.requestID == requestID, receipt.conversationID == conversationID,
              receipt.sessionID == sessionID, receipt.assistantMessageID == UUID(uuidString: assistantID),
              receipt.scope == scope, let actualRevision = privacyRevision,
              receipt.privacyRevision == actualRevision,
              scope == .conversationOnly ? actualRevision >= context.privacyRevision : actualRevision == context.privacyRevision,
              !receipt.provider.vendor.isEmpty, !receipt.provider.model.isEmpty, !receipt.provider.routeVersion.isEmpty,
              SupportChatTimestamp.date(receipt.createdAt) != nil,
              receipt.sources.allSatisfy({ source in
                  source.revision >= 0 && ["message", "companion_memory", "daily_intent", "session", "activity_result", "safety_policy"].contains(source.kind)
                    && (source.kind != "session" || source.id == context.sessionID)
                    && (scope != .conversationOnly || !["companion_memory", "daily_intent"].contains(source.kind))
              }) else { return false }
        if let proposal {
            guard status == "completed", !suppressOrdinaryCards, contentOrigin != .safetyResponse,
                  proposal.status == "offered", proposal.expiry != nil,
                  ["current_request", "approved_preference", "selected_intent", "general_option"].contains(proposal.reasonCode),
                  proposal.suggestedStep == nil || (proposal.template == .chooseStepV1 && proposal.suggestedStep!.unicodeScalars.count <= 400) else { return false }
        }
        return true
    }

    func actionableProposal(now: Date, scope currentScope: SupportContextScope, privacyRevision currentRevision: Int64) -> SupportChatProposal? {
        guard confirmed, status == "completed", !suppressOrdinaryCards, contentOrigin != .safetyResponse,
              scope == currentScope, privacyRevision == currentRevision, let proposal,
              proposal.status == "offered", let expiry = proposal.expiry, expiry > now else { return nil }
        return proposal
    }
}

enum SupportChatTimestamp {
    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct SupportChatCapabilities: Decodable, Equatable, Sendable {
    let chatContract: Int?
    let sessionContract: Int?
    let contextPolicy: Int?
    let privacyRevision: Bool?
    let chatConfirmation: Bool?
    enum CodingKeys: String, CodingKey {
        case chatContract = "chat_contract", sessionContract = "session_contract", contextPolicy = "context_policy"
        case privacyRevision = "privacy_revision", chatConfirmation = "chat_confirmation"
    }
    var allowsSessionChat: Bool {
        (chatContract ?? 0) >= 1 && (sessionContract ?? 0) >= 1 && (contextPolicy ?? 0) >= 1
            && privacyRevision == true && chatConfirmation == true
    }
}

struct SupportConversationCursor: Equatable, Sendable {
    /// The verbatim server timestamp retains the precision of the cursor; nil pages undated legacy records.
    let updatedAt: String?
    let id: UUID
}

struct SupportConversationPage {
    let items: [Conversation]
    let nextCursor: SupportConversationCursor?
}
