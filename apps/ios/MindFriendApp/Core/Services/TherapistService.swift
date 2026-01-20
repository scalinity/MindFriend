//
//  TherapistService.swift
//  MindFriendApp
//
//  Service layer for Therapist/Coach Marketplace - Phase 1
//

import Foundation
import Supabase

// MARK: - Therapist Service Errors

enum TherapistServiceError: LocalizedError {
    case notAuthenticated
    case applicationAlreadyExists
    case profileNotFound
    case photoUploadFailed
    case invalidInput(String)
    case networkError
    case databaseError
    case duplicateKey

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .applicationAlreadyExists:
            return "You already have a pending application"
        case .profileNotFound:
            return "Therapist profile not found"
        case .photoUploadFailed:
            return "Failed to upload photo. Please try again."
        case .invalidInput(let message):
            return message
        case .networkError:
            return "Network error. Please check your connection and try again."
        case .databaseError:
            return "An error occurred. Please try again."
        case .duplicateKey:
            return "A profile already exists for this account"
        }
    }
}

// MARK: - Therapist Service

/// Service for therapist/coach marketplace operations.
/// Note: Loading state should be managed by ViewModels, not this service.
@MainActor
final class TherapistService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Error Classification

    /// Classifies a raw error into a service-specific error type.
    /// Sanitizes error messages to prevent internal information leakage.
    private func classifyError(_ error: Error) -> TherapistServiceError {
        let message = error.localizedDescription.lowercased()

        if message.contains("pgrst116") || message.contains("no rows") {
            return .profileNotFound
        }
        if message.contains("duplicate") || message.contains("23505") {
            return .duplicateKey
        }
        if message.contains("network") || message.contains("connection") || message.contains("timeout") {
            return .networkError
        }

        return .databaseError
    }

    // MARK: - Discovery

    /// Search for therapists with filters and pagination
    func searchTherapists(filters: TherapistSearchFilters) async throws -> TherapistSearchResult {
        do {
            // Build filter query first (all filter methods before transform methods)
            var filterQuery = supabase
                .from(Tables.therapistProfiles)
                .select()

            // Filter for verified and accepting clients
            if filters.verifiedOnly {
                filterQuery = filterQuery
                    .eq("verified", value: true)
                    .eq("accepts_new_clients", value: true)
            }

            // Filter by profile type
            if let profileType = filters.profileType {
                filterQuery = filterQuery.eq("profile_type", value: profileType.rawValue)
            }

            // Filter by specialty
            if let specialty = filters.specialty {
                filterQuery = filterQuery.contains("specialties", value: [specialty.rawValue])
            }

            // Apply sorting and pagination (transform methods last)
            let offset = filters.page * filters.pageSize

            let orderedQuery: PostgrestTransformBuilder
            switch filters.sortBy {
            case .ratingDescending:
                orderedQuery = filterQuery.order("rating_average", ascending: false)
            case .ratingAscending:
                orderedQuery = filterQuery.order("rating_average", ascending: true)
            case .priceAscending:
                orderedQuery = filterQuery.order("rate_60_min", ascending: true)
            case .priceDescending:
                orderedQuery = filterQuery.order("rate_60_min", ascending: false)
            case .newest:
                orderedQuery = filterQuery.order("created_at", ascending: false)
            }

            let response: [TherapistProfile] = try await orderedQuery
                .range(from: offset, to: offset + filters.pageSize - 1)
                .execute()
                .value

            // Determine if there are more results
            let hasMore = response.count == filters.pageSize

            return TherapistSearchResult(
                therapists: response,
                totalCount: offset + response.count + (hasMore ? 1 : 0),
                hasMore: hasMore,
                page: filters.page,
                pageSize: filters.pageSize
            )
        } catch {
            throw classifyError(error)
        }
    }

    /// Get a single therapist by ID
    func getTherapist(id: UUID) async throws -> TherapistProfile? {
        do {
            let response: TherapistProfile = try await supabase
                .from(Tables.therapistProfiles)
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            return response
        } catch {
            let classified = classifyError(error)
            if case .profileNotFound = classified {
                return nil
            }
            throw classified
        }
    }

    /// Get therapist profile by user ID
    func getTherapistByUserId(_ userId: UUID) async throws -> TherapistProfile? {
        do {
            let response: TherapistProfile = try await supabase
                .from(Tables.therapistProfiles)
                .select()
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value

            return response
        } catch {
            let classified = classifyError(error)
            if case .profileNotFound = classified {
                return nil
            }
            throw classified
        }
    }

    // MARK: - Application

    /// Submit a therapist/coach application
    func submitApplication(_ input: TherapistApplicationInput) async throws -> TherapistProfile {
        guard let user = try? await supabase.auth.session.user else {
            throw TherapistServiceError.notAuthenticated
        }

        // Check if already has an application (use direct query, not nested call)
        do {
            let existing: TherapistProfile = try await supabase
                .from(Tables.therapistProfiles)
                .select()
                .eq("user_id", value: user.id)
                .single()
                .execute()
                .value

            if existing.applicationStatus != .rejected {
                throw TherapistServiceError.applicationAlreadyExists
            }
        } catch {
            // Profile not found is expected - continue to create
            let classified = classifyError(error)
            if case .profileNotFound = classified {
                // No existing profile - proceed
            } else if case .applicationAlreadyExists = error as? TherapistServiceError {
                throw error
            } else {
                // Other error - rethrow
                throw classified
            }
        }

        // Validate input
        let trimmedDisplayName = input.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = input.bio.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedDisplayName.isEmpty {
            throw TherapistServiceError.invalidInput("Display name is required")
        }
        if trimmedBio.count < 50 {
            throw TherapistServiceError.invalidInput("Bio must be at least 50 characters")
        }
        if input.credentials.isEmpty {
            throw TherapistServiceError.invalidInput("At least one credential is required")
        }
        if input.specialties.isEmpty {
            throw TherapistServiceError.invalidInput("At least one specialty is required")
        }

        // Validate rates if provided
        if let rate30 = input.rate30Min, rate30 < 0 {
            throw TherapistServiceError.invalidInput("Rate cannot be negative")
        }
        if let rate45 = input.rate45Min, rate45 < 0 {
            throw TherapistServiceError.invalidInput("Rate cannot be negative")
        }
        if let rate60 = input.rate60Min, rate60 < 0 {
            throw TherapistServiceError.invalidInput("Rate cannot be negative")
        }

        // Build insert data
        var insertData: [String: AnyJSON] = [
            "user_id": .string(user.id.uuidString),
            "profile_type": .string(input.profileType),
            "display_name": .string(trimmedDisplayName),
            "bio": .string(trimmedBio),
            "credentials": .array(input.credentials.map { .string($0) }),
            "specialties": .array(input.specialties.map { .string($0) }),
            "languages": .array(input.languages.map { .string($0) }),
            "application_status": .string("pending")
        ]

        if let approaches = input.approaches {
            insertData["approaches"] = .array(approaches.map { .string($0) })
        }

        if let licenseNumber = input.licenseNumber {
            insertData["license_number"] = .string(licenseNumber)
        }

        if let licenseState = input.licenseState {
            insertData["license_state"] = .string(licenseState)
        }

        if let rate30 = input.rate30Min {
            insertData["rate_30_min"] = .double(NSDecimalNumber(decimal: rate30).doubleValue)
        }

        if let rate45 = input.rate45Min {
            insertData["rate_45_min"] = .double(NSDecimalNumber(decimal: rate45).doubleValue)
        }

        if let rate60 = input.rate60Min {
            insertData["rate_60_min"] = .double(NSDecimalNumber(decimal: rate60).doubleValue)
        }

        do {
            let response: TherapistProfile = try await supabase
                .from(Tables.therapistProfiles)
                .insert(insertData)
                .select()
                .single()
                .execute()
                .value

            return response
        } catch {
            let classified = classifyError(error)
            if case .duplicateKey = classified {
                throw TherapistServiceError.applicationAlreadyExists
            }
            throw classified
        }
    }

    /// Get current user's therapist application/profile
    func getMyApplication() async throws -> TherapistProfile? {
        guard let user = try? await supabase.auth.session.user else {
            throw TherapistServiceError.notAuthenticated
        }

        return try await getTherapistByUserId(user.id)
    }

    /// Update therapist profile
    func updateProfile(_ updates: TherapistProfileUpdate) async throws -> TherapistProfile {
        guard let user = try? await supabase.auth.session.user else {
            throw TherapistServiceError.notAuthenticated
        }

        var updateData: [String: AnyJSON] = [:]

        if let displayName = updates.displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw TherapistServiceError.invalidInput("Display name cannot be empty")
            }
            updateData["display_name"] = .string(trimmed)
        }
        if let bio = updates.bio {
            let trimmed = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 50 {
                throw TherapistServiceError.invalidInput("Bio must be at least 50 characters")
            }
            updateData["bio"] = .string(trimmed)
        }
        if let photoUrl = updates.photoUrl {
            updateData["photo_url"] = .string(photoUrl)
        }
        if let credentials = updates.credentials {
            updateData["credentials"] = .array(credentials.map { .string($0) })
        }
        if let specialties = updates.specialties {
            updateData["specialties"] = .array(specialties.map { .string($0) })
        }
        if let approaches = updates.approaches {
            updateData["approaches"] = .array(approaches.map { .string($0) })
        }
        if let languages = updates.languages {
            updateData["languages"] = .array(languages.map { .string($0) })
        }
        if let licenseNumber = updates.licenseNumber {
            updateData["license_number"] = .string(licenseNumber)
        }
        if let licenseState = updates.licenseState {
            updateData["license_state"] = .string(licenseState)
        }
        if let rate30 = updates.rate30Min {
            if rate30 < 0 { throw TherapistServiceError.invalidInput("Rate cannot be negative") }
            updateData["rate_30_min"] = .double(NSDecimalNumber(decimal: rate30).doubleValue)
        }
        if let rate45 = updates.rate45Min {
            if rate45 < 0 { throw TherapistServiceError.invalidInput("Rate cannot be negative") }
            updateData["rate_45_min"] = .double(NSDecimalNumber(decimal: rate45).doubleValue)
        }
        if let rate60 = updates.rate60Min {
            if rate60 < 0 { throw TherapistServiceError.invalidInput("Rate cannot be negative") }
            updateData["rate_60_min"] = .double(NSDecimalNumber(decimal: rate60).doubleValue)
        }
        if let acceptsNewClients = updates.acceptsNewClients {
            updateData["accepts_new_clients"] = .bool(acceptsNewClients)
        }

        do {
            let response: TherapistProfile = try await supabase
                .from(Tables.therapistProfiles)
                .update(updateData)
                .eq("user_id", value: user.id)
                .select()
                .single()
                .execute()
                .value

            return response
        } catch {
            throw classifyError(error)
        }
    }

    // MARK: - Photo Management

    /// Upload therapist profile photo
    /// - Parameter imageData: JPEG image data
    /// - Returns: Public URL of the uploaded photo
    func uploadPhoto(imageData: Data) async throws -> String {
        guard let user = try? await supabase.auth.session.user else {
            throw TherapistServiceError.notAuthenticated
        }

        // Verify profile exists before upload
        guard try await getTherapistByUserId(user.id) != nil else {
            throw TherapistServiceError.profileNotFound
        }

        // Use user.id for path to match storage security policy
        let fileName = "profile.jpg"
        let filePath = "\(user.id.uuidString)/\(fileName)"

        do {
            // Upload to storage
            try await supabase.storage
                .from("therapist-photos")
                .upload(
                    path: filePath,
                    file: imageData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            // Get public URL
            let publicUrl = try supabase.storage
                .from("therapist-photos")
                .getPublicURL(path: filePath)

            // Update profile with new URL (direct query to avoid nested state issues)
            _ = try await supabase
                .from(Tables.therapistProfiles)
                .update(["photo_url": AnyJSON.string(publicUrl.absoluteString)])
                .eq("user_id", value: user.id)
                .execute()

            return publicUrl.absoluteString
        } catch {
            throw TherapistServiceError.photoUploadFailed
        }
    }

    /// Delete therapist profile photo
    func deletePhoto() async throws {
        guard let user = try? await supabase.auth.session.user else {
            throw TherapistServiceError.notAuthenticated
        }

        // Verify profile exists
        guard try await getTherapistByUserId(user.id) != nil else {
            throw TherapistServiceError.profileNotFound
        }

        // Use user.id for path to match storage security policy
        let filePath = "\(user.id.uuidString)/profile.jpg"

        do {
            try await supabase.storage
                .from("therapist-photos")
                .remove(paths: [filePath])

            // Clear photo URL in profile
            _ = try await supabase
                .from(Tables.therapistProfiles)
                .update(["photo_url": AnyJSON.null])
                .eq("user_id", value: user.id)
                .execute()
        } catch {
            throw TherapistServiceError.photoUploadFailed
        }
    }
}
