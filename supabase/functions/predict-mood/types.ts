// Predictive Mood Intelligence Types
// See: docs/specs/005-predictive-mood-intelligence.md

export interface PredictionFeatures {
  mood_avg_7d: number;
  mood_avg_14d: number;
  mood_trend_7d: number;
  previous_mood: number;
  sleep_hours: number | null;
  steps_yesterday: number | null;
  exercise_minutes_7d: number;
  day_of_week: number; // 0-6 (Sunday = 0)
  hour_of_day: number;
  streak_days: number;
  has_sleep_data: boolean;
  has_steps_data: boolean;
  timezone: string;
}

export interface FeatureWeights {
  sleep_hours: number;
  steps_yesterday: number;
  mood_avg_7d: number;
  mood_trend_7d: number;
  day_of_week: number;
  exercise_minutes: number;
}

export interface ContributingFactor {
  factor: string;
  impact: number;
  description: string;
}

export interface PredictionResult {
  predictedMood: number;
  confidence: number;
  factors: ContributingFactor[];
  modelVersion: string;
  featuresUsed: Partial<PredictionFeatures>;
}

export interface EligibleUser {
  user_id: string;
  timezone: string;
  mood_count: number;
  last_mood_at: string;
}

export interface MoodPrediction {
  id: string;
  user_id: string;
  predicted_for: string;
  predicted_mood: number;
  confidence: number;
  factors: ContributingFactor[];
  model_version: string;
  features_used: Partial<PredictionFeatures>;
  actual_mood: number | null;
  prediction_accuracy: number | null;
  notification_sent: boolean;
  created_at: string;
}

export interface InterventionRequest {
  userId: string;
  predictionId: string;
  predictedMood: number;
  factors: ContributingFactor[];
  features: Partial<PredictionFeatures>;
}

export type InterventionType =
  | "rest_suggestion"
  | "movement_suggestion"
  | "pattern_break"
  | "general_support";

export interface InterventionResponse {
  interventionId: string;
  type: InterventionType;
  content: string;
  suggestedExerciseId: string | null;
  notificationSent: boolean;
}
