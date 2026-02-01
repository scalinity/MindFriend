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
    /// - Returns: User profile, or nil if none exists yet
    func fetchProfile() async throws -> WellbeingDebtProfile? {
        let response: [WellbeingDebtProfile] = try await supabase
            .from("wellbeing_debt_profiles")
            .select()
            .execute()
            .value

        return response.first
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
            let response: RecoveryProgramResponse = try await supabase.functions
                .invoke(
                    "generate-recovery-program",
                    options: FunctionInvokeOptions(
                        body: request
                    )
                )

            // Check if user needs more data first
            if response.needsMoreData == true {
                let message = response.error ?? "Not enough data to generate a recovery program. Please track your mood and activities for a few days."
                throw WellbeingDebtError.needsMoreData(message)
            }

            guard response.success, let program = response.program else {
                let reason = response.error ?? "Unknown error"
                throw WellbeingDebtError.generationFailed(reason)
            }

            return program
        } catch let decodingError as DecodingError {
            // Provide more detailed error information for debugging
            switch decodingError {
            case .keyNotFound(let key, let context):
                throw WellbeingDebtError.generationFailed("Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                throw WellbeingDebtError.generationFailed("Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                throw WellbeingDebtError.generationFailed("Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                throw WellbeingDebtError.generationFailed("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default:
                throw WellbeingDebtError.generationFailed("Decoding error: \(decodingError.localizedDescription)")
            }
        } catch let wellbeingError as WellbeingDebtError {
            throw wellbeingError
        } catch {
            throw WellbeingDebtError.generationFailed(error.localizedDescription)
        }
    }

    /// Save a recovery program to the database
    /// - Parameter program: The recovery program to save
    /// - Returns: The saved program with server-generated ID
    func saveRecoveryProgram(_ program: RecoveryProgram) async throws -> RecoveryProgram {
        let userId = try await getCurrentUserId()
        
        // First, mark any existing active programs as abandoned
        try await supabase
            .from("recovery_programs")
            .update(["status": "abandoned"])
            .eq("user_id", value: userId)
            .eq("status", value: "active")
            .execute()
        
        // Insert the new program
        struct SavedProgram: Codable {
            let id: UUID?
            let userId: String
            let generatedAt: String
            let targetDebtReduction: Decimal
            let dailyActions: [DailyActions]
            let status: String
            
            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case generatedAt = "generated_at"
                case targetDebtReduction = "target_debt_reduction"
                case dailyActions = "daily_actions"
                case status
            }
        }
        
        let toSave = SavedProgram(
            id: nil,
            userId: userId,
            generatedAt: program.generatedAt,
            targetDebtReduction: program.targetDebtReduction,
            dailyActions: program.dailyActions,
            status: "active"
        )
        
        let saved: SavedProgram = try await supabase
            .from("recovery_programs")
            .insert(toSave)
            .select()
            .single()
            .execute()
            .value
        
        // Return updated program with ID
        return RecoveryProgram(
            userId: saved.userId,
            generatedAt: saved.generatedAt,
            targetDebtReduction: saved.targetDebtReduction,
            dailyActions: saved.dailyActions
        )
    }
    
    /// Fetch the user's active recovery program
    /// - Returns: Active recovery program, or nil if none exists
    func fetchActiveRecoveryProgram() async throws -> RecoveryProgram? {
        let userId = try await getCurrentUserId()
        
        // Select only the fields we need and filter by user_id explicitly
        let response: [RecoveryProgram] = try await supabase
            .from("recovery_programs")
            .select("user_id, generated_at, target_debt_reduction, daily_actions")
            .eq("user_id", value: userId)
            .eq("status", value: "active")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }

    // MARK: - Helper Methods

    /// Get the current authenticated user ID
    /// - Returns: User ID
    private func getCurrentUserId() async throws -> String {
        let userId = try await supabase.auth.session.user.id.uuidString
        return userId
    }

    /// Manually trigger debt score calculation for the current user
    /// - Parameter date: Optional date (defaults to yesterday)
    /// - Returns: Calculated debt score
    func calculateDebtScore(for date: String? = nil) async throws -> DebtScore {
        struct CalculateRequest: Encodable {
            let date: String?
        }

        let response: CalculateResponse = try await supabase.functions
            .invoke(
                "calculate-debt-score",
                options: FunctionInvokeOptions(body: CalculateRequest(date: date))
            )

        guard response.success, let score = response.score else {
            throw WellbeingDebtError.generationFailed("Failed to calculate debt score")
        }

        return score
    }

    /// Trigger transaction detection for a specific date
    /// - Parameter date: Date in YYYY-MM-DD format (defaults to yesterday)
    /// - Returns: Number of transactions detected
    @discardableResult
    func triggerTransactionDetection(for date: String? = nil) async throws -> Int {
        struct DetectRequest: Encodable {
            let date: String?
        }

        struct DetectResponse: Decodable {
            let success: Bool
            let transactionsCount: Int?

            enum CodingKeys: String, CodingKey {
                case success
                case transactionsCount = "transactions_count"
            }
        }

        let response: DetectResponse = try await supabase.functions
            .invoke(
                "detect-transactions",
                options: FunctionInvokeOptions(body: DetectRequest(date: date))
            )

        guard response.success else {
            throw WellbeingDebtError.generationFailed("Failed to detect transactions")
        }

        return response.transactionsCount ?? 0
    }

    /// Backfill transactions from account creation date (max N days)
    /// - Parameter days: Maximum number of days to backfill (default 30)
    /// - Returns: Total number of transactions detected across all days
    func backfillTransactions(days: Int = 30) async throws -> Int {
        // Get account creation date to avoid backfilling before user existed
        let accountCreatedAt = try await fetchAccountCreationDate()
        let today = Date()

        // Calculate days since account creation
        let daysSinceCreation = Calendar.current.dateComponents(
            [.day],
            from: accountCreatedAt,
            to: today
        ).day ?? 0

        // Only backfill from account creation, capped at max days
        let daysToBackfill = min(days, max(0, daysSinceCreation))

        if daysToBackfill == 0 {
            return 0 // Account created today, nothing to backfill
        }

        var totalTransactions = 0

        for i in 1...daysToBackfill {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!

            // Skip if date is before account creation
            if date < accountCreatedAt {
                continue
            }

            let dateString = formatDate(date)
            let count = try await triggerTransactionDetection(for: dateString)
            totalTransactions += count
        }

        return totalTransactions
    }

    /// Fetch the user's account creation date from profiles table
    /// - Returns: Account creation date
    private func fetchAccountCreationDate() async throws -> Date {
        struct ProfileCreatedAt: Decodable {
            let createdAt: Date

            enum CodingKeys: String, CodingKey {
                case createdAt = "created_at"
            }
        }

        let response: [ProfileCreatedAt] = try await supabase
            .from("profiles")
            .select("created_at")
            .limit(1)
            .execute()
            .value

        guard let profile = response.first else {
            // Fallback to today if profile not found (shouldn't happen)
            return Date()
        }

        return profile.createdAt
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
