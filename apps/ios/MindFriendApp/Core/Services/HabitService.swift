import Foundation
import Supabase

// MARK: - Habit Service Errors

enum HabitServiceError: LocalizedError {
    case habitNotFound
    case routineNotFound
    case duplicateCompletion
    case invalidDuration
    case invalidStreak
    case supabaseError(String)
    case decodingError(String)
    case invalidHabitState(String)
    
    var errorDescription: String? {
        switch self {
        case .habitNotFound:
            return "The habit could not be found"
        case .routineNotFound:
            return "The routine could not be found"
        case .duplicateCompletion:
            return "This habit was already completed today"
        case .invalidDuration:
            return "The duration must be between 1 and 600 seconds"
        case .invalidStreak:
            return "Invalid streak calculation"
        case .supabaseError(let message):
            return "Database error: \(message)"
        case .decodingError(let message):
            return "Failed to decode data: \(message)"
        case .invalidHabitState(let message):
            return message
        }
    }
}

// MARK: - Habit Service

@MainActor
final class HabitService: ObservableObject {
    @Published var habits: [Habit] = []
    @Published var routines: [Routine] = []
    @Published var habitTemplates: [HabitTemplate] = []
    @Published var isLoading = false
    @Published var error: HabitServiceError?

    private let supabase: SupabaseClient

    // Configuration constants
    private enum HabitConfig {
        static let defaultReminderMinutesBefore = 5
        static let graduationStreakThreshold = 7
        static let maxGracePeriodDays = 2
        static let weekStatsDays = 7
    }

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    // MARK: - Habit CRUD Operations
    
    /// Fetch all active habits for the current user
    func fetchHabits() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let response: [Habit] = try await supabase
            .from("habits")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
        
        self.habits = response
    }
    
    /// Create a new habit from user input
    func createHabit(
        name: String,
        anchor: String,
        behavior: String,
        category: HabitCategory,
        difficulty: HabitDifficulty,
        reminderTime: Date?
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        guard difficulty.defaultDuration > 0 && difficulty.defaultDuration <= HabitDifficulty.maxDuration else {
            throw HabitServiceError.invalidDuration
        }
        
        let habit = Habit(
            id: UUID(),
            userId: userId,
            name: name,
            anchor: anchor,
            behavior: behavior,
            category: category,
            difficulty: difficulty,
            durationSeconds: difficulty.defaultDuration,
            reminderTime: reminderTime,
            reminderMinutesBefore: HabitConfig.defaultReminderMinutesBefore,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // PostgREST insert returns an empty body by default (Prefer: return=minimal)
        // so don't try to decode `.value` — we refresh via fetchHabits() below.
        try await supabase
            .from("habits")
            .insert(habit)
            .execute()

        try await fetchHabits()
    }

    /// Create a habit from a template
    func createHabitFromTemplate(
        template: HabitTemplate,
        anchor: String
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id

        let behavior = template.behaviorTemplate

        let habit = Habit(
            id: UUID(),
            userId: userId,
            name: template.name,
            anchor: anchor,
            behavior: behavior,
            category: template.category,
            difficulty: template.difficulty,
            durationSeconds: template.defaultDurationSeconds,
            reminderTime: nil,
            reminderMinutesBefore: HabitConfig.defaultReminderMinutesBefore,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await supabase
            .from("habits")
            .insert(habit)
            .execute()

        try await fetchHabits()
    }
    
    /// Soft delete a habit (set is_active to false)
    func deleteHabit(_ habit: Habit) async throws {
        let updated = Habit(
            id: habit.id,
            userId: habit.userId,
            name: habit.name,
            anchor: habit.anchor,
            behavior: habit.behavior,
            category: habit.category,
            difficulty: habit.difficulty,
            durationSeconds: habit.durationSeconds,
            reminderTime: habit.reminderTime,
            reminderMinutesBefore: habit.reminderMinutesBefore,
            isActive: false,
            createdAt: habit.createdAt,
            updatedAt: Date()
        )
        
        try await supabase
            .from("habits")
            .update(updated)
            .eq("id", value: habit.id.uuidString)
            .execute()

        try await fetchHabits()
    }
    
    // MARK: - Habit Completion Tracking
    
    /// Mark a habit as completed for today
    /// Handles streak calculation: increments streak if yesterday was completed, resets if skipped or 3+ days gap
    func completeHabit(_ habit: Habit) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // Check for duplicate completion today
        let existing: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habit.id.uuidString)
            .eq("completed_date", value: HabitDateFormatter.dayOnly.string(from: today))
            .execute()
            .value
        
        if !existing.isEmpty {
            throw HabitServiceError.duplicateCompletion
        }
        
        // Calculate streak
        let newStreak = try await calculateStreak(habitId: habit.id, userId: userId)
        
        let completion = HabitCompletion(
            id: UUID(),
            habitId: habit.id,
            userId: userId,
            completedDate: today,
            currentStreak: newStreak,
            skipped: false,
            skipReason: nil,
            createdAt: Date()
        )
        
        try await supabase
            .from("habit_completions")
            .insert(completion)
            .execute()

        // Check if habit should graduate (7-day streak)
        if newStreak >= HabitConfig.graduationStreakThreshold &&
           newStreak % HabitConfig.graduationStreakThreshold == 0 {
            try await checkForGraduation(habit: habit, streak: newStreak)
        }
    }
    
    /// Skip a habit for today (resets streak to 0)
    func skipHabit(_ habit: Habit, reason: String? = nil) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // Check for duplicate entry today
        let existing: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habit.id.uuidString)
            .eq("completed_date", value: HabitDateFormatter.dayOnly.string(from: today))
            .execute()
            .value
        
        if !existing.isEmpty {
            throw HabitServiceError.duplicateCompletion
        }
        
        let completion = HabitCompletion(
            id: UUID(),
            habitId: habit.id,
            userId: userId,
            completedDate: today,
            currentStreak: 0,  // Streak resets on skip
            skipped: true,
            skipReason: reason,
            createdAt: Date()
        )
        
        try await supabase
            .from("habit_completions")
            .insert(completion)
            .execute()
    }
    
    // MARK: - Streak Calculation
    
    /// Calculate current streak for a habit
    /// Logic: 
    /// - First completion: streak = 1
    /// - Ongoing: if yesterday completed, streak += 1
    /// - Skip or 3+ day gap: streak = 0
    private func calculateStreak(habitId: UUID, userId: UUID) async throws -> Int {
        let completions: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habitId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .order("completed_date", ascending: false)
            .limit(3)
            .execute()
            .value
        
        guard !completions.isEmpty else {
            // First completion
            return 1
        }
        
        let today = Calendar.current.startOfDay(for: Date())

        guard let lastCompletion = completions.first else {
            // Should not happen due to guard above, but be safe
            return 1
        }
        
        // If last completion was skipped, reset streak
        if lastCompletion.skipped {
            return 1  // New streak starts today
        }
        
        let daysBetween = Calendar.current.dateComponents([.day], from: lastCompletion.completedDate, to: today).day ?? 0

        switch daysBetween {
        case 0:
            // Same day (shouldn't happen, but handle it)
            return lastCompletion.currentStreak
        case 1:
            // Yesterday was completed, continue streak
            return lastCompletion.currentStreak + 1
        case 2:
            // Missed yesterday, but within grace period
            return lastCompletion.currentStreak + 1
        default:
            // 3+ days gap, reset streak
            return 1
        }
    }
    
    /// Get current streak for a habit
    func getCurrentStreak(for habit: Habit) async throws -> HabitStreakInfo {
        let session = try await supabase.auth.session
        let userId = session.user.id

        let completions: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habit.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .order("completed_date", ascending: false)
            .execute()
            .value

        let today = Calendar.current.startOfDay(for: Date())

        // Calculate actual current streak based on last completion
        var currentStreak = 0
        var isCompletedToday = false

        if let lastCompletion = completions.first {
            isCompletedToday = lastCompletion.completedDate == today && !lastCompletion.skipped

            if lastCompletion.skipped {
                currentStreak = 0
            } else {
                let daysBetween = Calendar.current.dateComponents([.day], from: lastCompletion.completedDate, to: today).day ?? 0

                switch daysBetween {
                case 0:
                    // Completed today
                    currentStreak = lastCompletion.currentStreak
                case 1, 2:
                    // Within grace period but not completed today yet
                    currentStreak = lastCompletion.currentStreak
                default:
                    // Gap too large, streak is broken
                    currentStreak = 0
                }
            }
        }

        let longestStreak = completions.map { $0.currentStreak }.max() ?? 0
        let lastCompletionDate = completions.first?.completedDate

        // Will reset if not completed today and currently have an active streak
        let willReset = !isCompletedToday && currentStreak > 0

        return HabitStreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastCompletionDate: lastCompletionDate,
            isCompletedToday: isCompletedToday,
            willResetNextDay: willReset
        )
    }
    
    // MARK: - Habit Graduation (Difficulty Increase)
    
    /// Check if habit should graduate after 7-day streak
    private func checkForGraduation(habit: Habit, streak: Int) async throws {
        // Implement graduation logic: increase difficulty after 7-day consecutive streak
        // This will trigger a UI notification for the user to accept/decline
        // For now, just log that graduation is available
        // Full implementation will be in the view layer
    }
    
    // MARK: - Templates
    
    /// Fetch all available habit templates
    func fetchHabitTemplates() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response: [HabitTemplate] = try await supabase
            .from("habit_templates")
            .select()
            .execute()
            .value
        
        self.habitTemplates = response
    }
    
    // MARK: - Routine Operations
    
    /// Fetch all active routines for the current user
    func fetchRoutines() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let response: [Routine] = try await supabase
            .from("routines")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
        
        self.routines = response
    }
    
    /// Create a new routine
    func createRoutine(
        name: String,
        type: RoutineType,
        targetTime: Date?
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let routine = Routine(
            id: UUID(),
            userId: userId,
            name: name,
            type: type,
            targetTime: targetTime,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await supabase
            .from("routines")
            .insert(routine)
            .execute()

        try await fetchRoutines()
    }
    
    /// Get routine with all its habits
    func getRoutineWithHabits(_ routine: Routine) async throws -> RoutineWithHabits {
        let routineHabits: [RoutineHabit] = try await supabase
            .from("routine_habits")
            .select()
            .eq("routine_id", value: routine.id.uuidString)
            .order("order_index", ascending: true)
            .execute()
            .value
        
        let habitIds = routineHabits.map { $0.habitId.uuidString }
        
        var habitsInRoutine: [Habit] = []
        if !habitIds.isEmpty {
            habitsInRoutine = try await supabase
                .from("habits")
                .select()
                .in("id", values: habitIds)
                .execute()
                .value
        }
        
        // Sort habits by routine order
        let habitMap = Dictionary(uniqueKeysWithValues: habitsInRoutine.map { ($0.id, $0) })
        let sortedHabits = routineHabits.compactMap { habitMap[$0.habitId] }
        
        return RoutineWithHabits(routine: routine, habits: sortedHabits)
    }
    
    /// Add a habit to a routine
    func addHabitToRoutine(_ habit: Habit, routine: Routine, at index: Int) async throws {
        let routineHabit = RoutineHabit(
            routineId: routine.id,
            habitId: habit.id,
            orderIndex: index,
            createdAt: Date()
        )
        
        try await supabase
            .from("routine_habits")
            .insert(routineHabit)
            .execute()
    }
    
    /// Complete a routine
    func completeRoutine(
        _ routine: Routine,
        completedHabitIds: [UUID],
        skippedHabitIds: [UUID]
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let today = Calendar.current.startOfDay(for: Date())
        let totalHabits = completedHabitIds.count + skippedHabitIds.count
        let completionPercentage = totalHabits > 0 ? (completedHabitIds.count * 100) / totalHabits : 0
        
        // Calculate total duration from completed habits
        let completedHabits: [Habit] = try await supabase
            .from("habits")
            .select()
            .in("id", values: completedHabitIds.map { $0.uuidString })
            .execute()
            .value
        
        let totalDuration = completedHabits.reduce(0) { $0 + $1.durationSeconds }
        
        let completion = RoutineCompletion(
            id: UUID(),
            routineId: routine.id,
            userId: userId,
            completedDate: today,
            completedHabitIds: completedHabitIds,
            skippedHabitIds: skippedHabitIds,
            completionPercentage: completionPercentage,
            totalDurationSeconds: totalDuration,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await supabase
            .from("routine_completions")
            .insert(completion)
            .execute()
    }
    
    // MARK: - Weekly Stats
    
    /// Get weekly completion stats for a habit
    func getWeeklyStats(for habit: Habit) async throws -> [Int] {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        let today = Calendar.current.startOfDay(for: Date())
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: today)!
        
        let completions: [HabitCompletion] = try await supabase
            .from("habit_completions")
            .select()
            .eq("habit_id", value: habit.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .gte("completed_date", value: ISO8601DateFormatter().string(from: weekAgo))
            .lte("completed_date", value: ISO8601DateFormatter().string(from: today))
            .execute()
            .value
        
        // Build array of 7 days (0 = not completed, 1 = completed)
        var weekStats = Array(repeating: 0, count: 7)
        
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: i - 6, to: today)!
            let completed = completions.contains { Calendar.current.isDate($0.completedDate, inSameDayAs: date) && !$0.skipped }
            weekStats[i] = completed ? 1 : 0
        }
        
        return weekStats
    }
}
