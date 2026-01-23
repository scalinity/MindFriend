// Suggest Intervention Types
// See: docs/specs/005-predictive-mood-intelligence.md

export interface ContributingFactor {
  factor: string;
  impact: number;
  description: string;
}

export interface InterventionRequest {
  userId: string;
  predictionId: string;
  predictedMood: number;
  factors: ContributingFactor[];
  features: {
    sleep_hours?: number | null;
    steps_yesterday?: number | null;
    mood_trend_7d?: number;
    exercise_minutes_7d?: number;
    day_of_week?: number;
    streak_days?: number;
  };
}

export type InterventionType =
  | "rest_suggestion"
  | "movement_suggestion"
  | "pattern_break"
  | "general_support";

export interface InterventionContent {
  type: InterventionType;
  message: string;
  exerciseCategory: string | null;
}

export interface MatchedExercise {
  id: string;
  title: string;
  type: string;
  duration_minutes: number;
}
