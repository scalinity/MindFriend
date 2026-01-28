import Foundation

/// Service that maps assessment results to personalized exercise recommendations
/// Based on clinical evidence for each severity level and assessment type
@MainActor
final class AssessmentRecommendationService: ObservableObject {

    init() {}

    // MARK: - Public API

    /// Get exercise recommendations based on assessment results
    func getRecommendations(
        assessmentCode: String,
        severityLevel: String,
        maxCount: Int = 5
    ) async throws -> [AssessmentExerciseRecommendation] {
        // Get recommended exercise types for this assessment + severity
        let recommendedTypes = getRecommendedTypes(
            assessmentCode: assessmentCode,
            severityLevel: severityLevel
        )

        guard !recommendedTypes.isEmpty else { return [] }

        // Fetch exercises from database filtered by type
        let exercises = try await fetchExercises(types: recommendedTypes)

        // Map to recommendations with context
        let recommendations = exercises.prefix(maxCount).enumerated().map { index, exercise in
            AssessmentExerciseRecommendation(
                exercise: exercise,
                reason: getReason(
                    assessmentCode: assessmentCode,
                    severityLevel: severityLevel,
                    exerciseType: exercise.type
                ),
                priority: index + 1
            )
        }

        return Array(recommendations)
    }

    // MARK: - Recommendation Logic

    /// Maps assessment type + severity to recommended exercise types
    /// Based on clinical evidence for symptom management
    private func getRecommendedTypes(
        assessmentCode: String,
        severityLevel: String
    ) -> [ExerciseType] {
        let severity = severityLevel.lowercased()

        switch assessmentCode {
        case "PHQ9":
            // Depression: Focus on activation and mood regulation
            switch severity {
            case "minimal":
                return [.breathing, .journaling, .meditation, .movement]
            case "mild":
                return [.breathing, .journaling, .grounding]
            case "moderate":
                return [.meditation, .grounding, .movement, .breathing]
            case "moderately_severe", "moderately severe":
                return [.grounding, .breathing] // Shorter, simpler exercises
            case "severe":
                return [.grounding] // Crisis-appropriate only
            default:
                return [.breathing, .grounding]
            }

        case "GAD7":
            // Anxiety: Focus on calming and grounding
            switch severity {
            case "minimal":
                return [.breathing, .grounding, .meditation]
            case "mild":
                return [.breathing, .grounding, .meditation]
            case "moderate":
                return [.grounding, .breathing] // Avoid long meditation
            case "severe":
                return [.grounding, .breathing] // Quick calming techniques
            default:
                return [.breathing, .grounding]
            }

        case "WHO5":
            // Well-being: Focus on building positive activities
            switch severity {
            case "excellent", "good":
                return [.meditation, .journaling, .movement]
            case "moderate":
                return [.breathing, .journaling, .meditation]
            case "moderate_low", "moderately low":
                return [.breathing, .grounding, .journaling]
            case "low":
                return [.grounding, .breathing] // Gentle start
            default:
                return [.breathing, .journaling]
            }

        case "PSS10":
            // Stress: Focus on relaxation and perspective
            switch severity {
            case "low":
                return [.meditation, .journaling, .movement]
            case "moderate":
                return [.breathing, .meditation, .grounding]
            case "high":
                return [.breathing, .grounding] // Quick stress relief
            default:
                return [.breathing, .grounding]
            }

        default:
            return [.breathing, .grounding, .meditation]
        }
    }

    /// Get a contextual reason for why this exercise is recommended
    private func getReason(
        assessmentCode: String,
        severityLevel: String,
        exerciseType: ExerciseType
    ) -> String {
        let severity = severityLevel.lowercased()

        // Depression-specific reasons (PHQ-9)
        if assessmentCode == "PHQ9" {
            switch exerciseType {
            case .breathing:
                if severity == "severe" || severity == "moderately_severe" {
                    return "Quick relief for overwhelming feelings"
                }
                return "Helps activate your body's calm response"
            case .grounding:
                if severity == "severe" {
                    return "Gentle technique to stay present in difficult moments"
                }
                return "Reconnects you with the present moment"
            case .journaling:
                return "Process and understand your thoughts"
            case .meditation:
                return "Build awareness and self-compassion"
            case .movement:
                return "Activate your body to lift mood naturally"
            }
        }

        // Anxiety-specific reasons (GAD-7)
        if assessmentCode == "GAD7" {
            switch exerciseType {
            case .breathing:
                return "Activates your body's natural calm response"
            case .grounding:
                if severity == "severe" || severity == "moderate" {
                    return "Quick way to reduce anxious thoughts"
                }
                return "Anchors you in the present moment"
            case .journaling:
                return "Externalize worries to gain perspective"
            case .meditation:
                if severity == "moderate" || severity == "severe" {
                    return "Short practice to quiet racing thoughts"
                }
                return "Build capacity to observe anxious thoughts"
            case .movement:
                return "Release physical tension from anxiety"
            }
        }

        // Well-being reasons (WHO-5)
        if assessmentCode == "WHO5" {
            switch exerciseType {
            case .breathing:
                return "Start your day with calm energy"
            case .grounding:
                return "Find stability during challenging moments"
            case .journaling:
                return "Reflect on what brings you joy"
            case .meditation:
                return "Cultivate inner peace and presence"
            case .movement:
                return "Boost energy and positive mood"
            }
        }

        // Stress-specific reasons (PSS-10)
        if assessmentCode == "PSS10" {
            switch exerciseType {
            case .breathing:
                return "Quick way to lower stress hormones"
            case .grounding:
                return "Break the stress cycle"
            case .journaling:
                return "Gain perspective on stressors"
            case .meditation:
                return "Build resilience to daily stress"
            case .movement:
                return "Release physical tension from stress"
            }
        }

        // Default reasons
        switch exerciseType {
        case .breathing:
            return "Calm your nervous system"
        case .grounding:
            return "Stay present and centered"
        case .journaling:
            return "Process your thoughts and feelings"
        case .meditation:
            return "Build awareness and peace"
        case .movement:
            return "Energize your body and mind"
        }
    }

    // MARK: - Data Fetching

    private func fetchExercises(types: [ExerciseType]) async throws -> [Exercise] {
        let typeStrings = types.map { $0.rawValue }

        // Fetch from Supabase using global client
        let exercises: [Exercise] = try await supabase
            .from("exercises")
            .select()
            .in("type", values: typeStrings)
            .eq("is_premium", value: false) // Start with free exercises
            .limit(20)
            .execute()
            .value

        // Sort by recommended type order
        let typeOrder = Dictionary(uniqueKeysWithValues: types.enumerated().map { ($1, $0) })
        return exercises.sorted { ex1, ex2 in
            let order1 = typeOrder[ex1.type] ?? 999
            let order2 = typeOrder[ex2.type] ?? 999
            if order1 != order2 {
                return order1 < order2
            }
            // Secondary sort by duration (shorter first for severe cases)
            return ex1.durationSeconds < ex2.durationSeconds
        }
    }
}

// MARK: - Recommendation Model

/// An exercise recommendation with context for why it was suggested
struct AssessmentExerciseRecommendation: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let reason: String
    let priority: Int

    var exerciseType: ExerciseType { exercise.type }
    var title: String { exercise.title }
    var duration: Int { exercise.durationSeconds }

    var durationLabel: String {
        let minutes = duration / 60
        if minutes < 1 {
            return "\(duration)s"
        }
        return "\(minutes) min"
    }
}
