// AIConsentErrorMapper.swift
// Surfaces 403 ai_consent_required Edge Function responses as typed AIConsentRequiredError.

import Foundation
import Supabase

private struct AIConsentErrorBody: Decodable {
    let code: String
    let feature: String
}

enum AIConsentErrorMapper {
    /// If `error` is a `FunctionsError.httpError(403, body)` whose JSON body has
    /// `code == "ai_consent_required"`, returns an `AIConsentRequiredError` and
    /// notifies `AIConsentService` to flip the in-memory state for that feature.
    /// Otherwise returns `nil` so the caller can rethrow the original error.
    static func decode(_ error: Error, consentService: AIConsentService?) async -> AIConsentRequiredError? {
        guard
            let fnError = error as? FunctionsError,
            case .httpError(let status, let data) = fnError,
            status == 403,
            let body = try? JSONDecoder().decode(AIConsentErrorBody.self, from: data),
            body.code == "ai_consent_required",
            let feature = AIFeature(rawValue: body.feature)
        else {
            return nil
        }
        if let service = consentService {
            await MainActor.run { service.markUnknown(feature) }
        }
        return AIConsentRequiredError(feature: feature)
    }
}
