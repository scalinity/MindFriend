//
//  WellbeingDebtService.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator
//  Service for managing wellbeing debt scores, profiles, and recovery programs
//

import Foundation
import Supabase

/// Service for managing wellbeing debt tracking and recovery
actor WellbeingDebtService {
    // MARK: - Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Debt Score Operations

    /// Fetch the most recent debt score for the current user
    /// - Returns: Latest debt score, or nil if none exists
    func fetchLatestDebtScore() async throws -> DebtScore? {
        let response: [DebtScore] = try await supabase
            .from("wellbeing_debt_scores")
            .select()
            .order("date", ascending: false)
            .limit(1)
            .execute()
            .value

        return response.first
    }

    /// Fetch debt scores for a specific date range
    /// - Parameters:
    ///   - startDate: Start date in YYYY-MM-DD format
    ///   - endDate: End date in YYYY-MM-DD format
    /// - Returns: Array of debt scores within the range
    func fetchDebtScores(from startDate: String, to endDate: String) async throws -> [DebtScore] {
        let response: [DebtScore] = try await supabase
            .from("wellbeing_debt_scores")
            .select()
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date", ascending: true)
            .execute()
            .value

        return response
    }

    /// Fetch debt score for a specific date
    /// - Parameter date: Date in YYYY-MM-DD format
    /// - Returns: Debt score for the date, or nil if none exists
    func fetchDebtScore(for date: String) async throws -> DebtScore? {
        let response: [DebtScore] = try await supabase
            .from("wellbeing_debt_scores")
            .select()
            .eq("date", value: date)
            .execute()
            .value

        return response.first
    }

    // MARK: - Transaction Operations

    /// Fetch transactions for a specific date range
    /// - Parameters:
    ///   - startDate: Start date in YYYY-MM-DD format
    ///   - endDate: End date in YYYY-MM-DD format
    /// - Returns: Array of transactions within the range
    func fetchTransactions(from startDate: String, to endDate: String) async throws -> [WellbeingTransaction] {
        let response: [WellbeingTransaction] = try await supabase
            .from("wellbeing_transactions")
            .select()
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetch transactions for a specific date
    /// - Parameter date: Date in YYYY-MM-DD format
    /// - Returns: Array of transactions for the date
    func fetchTransactions(for date: String) async throws -> [WellbeingTransaction] {
        let response: [WellbeingTransaction] = try await supabase
            .from("wellbeing_transactions")
            .select()
            .eq("date", value: date)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    /// Manually log a user-created transaction
    /// - Parameters:
    ///   - date: Date in YYYY-MM-DD format
    ///   - type: Transaction type (deposit or withdrawal)
    ///   - category: Transaction category
    ///   - amount: Transaction amount
    ///   - description: Optional description
    /// - Returns: The created transaction
    func logTransaction(
        date: String,
        type: TransactionType,
        category: TransactionCategory,
        amount: Decimal,
        description: String?
    ) async throws -> WellbeingTransaction {
        let transaction = WellbeingTransaction(
            id: UUID(),
            userId: try await getCurrentUserId(),
            date: date,
            type: type,
            category: category,
            amount: amount,
            source: TransactionSource.userLogged,
            description: description,
            metadata: nil as [String: WellbeingAnyCodable]?,
            createdAt: Date()
        )

        let response: WellbeingTransaction = try await supabase
            .from("wellbeing_transactions")
            .insert(transaction)
            .select()
            .single()
            .execute()
            .value

        return response
    }

    // MARK: - Profile Operations

    /// Fetch the user's wellbeing debt profile
    /// - Returns: User profile
    func fetchProfile() async throws -> WellbeingDebtProfile {
        let response: [WellbeingDebtProfile] = try await supabase
            .from("wellbeing_debt_profiles")
            .select()
            .execute()
            .value

        guard let profile = response.first else {
            throw WellbeingDebtError.profileNotFound
        }

        return profile
    }

    // MARK: - Recovery Program Operations

    /// Generate a personalized recovery program via Edge Function
    /// - Parameters:
    ///   - startDate: Optional start date (defaults to today)
    ///   - intensity: Program intensity (gentle, moderate, aggressive)
    /// - Returns: Generated recovery program
    func generateRecoveryProgram(
        startDate: String? = nil,
        intensity: String = "moderate"
    ) async throws -> RecoveryProgram {
        let request = GenerateRecoveryRequest(
            startDate: startDate,
            intensity: intensity
        )

        do {
            let response: RecoveryProgram = try await supabase.functions
                .invoke(
                    "generate-recovery-program",
                    options: FunctionInvokeOptions(
                        body: request
                    )
                )

            return response
        } catch {
            throw WellbeingDebtError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    /// Get the current authenticated user ID
    /// - Returns: User ID
    private func getCurrentUserId() async throws -> String {
        let userId = try await supabase.auth.session.user.id.uuidString
        return userId
    }

    /// Format a Date to YYYY-MM-DD string
    /// - Parameter date: Date to format
    /// - Returns: ISO date string
    func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// Parse YYYY-MM-DD string to Date
    /// - Parameter dateString: ISO date string
    /// - Returns: Date object
    func parseDate(_ dateString: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: dateString) else {
            throw WellbeingDebtError.invalidDate(dateString)
        }
        return date
    }
}

// MARK: - Request Models

struct GenerateRecoveryRequest: Codable {
    let startDate: String?
    let intensity: String

    enum CodingKeys: String, CodingKey {
        case startDate
        case intensity
    }
}
