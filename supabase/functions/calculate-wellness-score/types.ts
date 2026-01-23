// TypeScript type definitions for Daily Wellness Score feature
// Defines interfaces for score calculation inputs/outputs

export interface WellnessScoreInput {
  userId: string;
  date: string; // ISO 8601 format (YYYY-MM-DD)

  // Mood data (from moods table) - EXPANDED to include anxiety & energy
  moods: Array<{
    moodScore: number; // 1-10
    anxietyScore?: number; // 1-10 (lower is better)
    energyScore?: number; // 1-10 (higher is better)
    timestamp: string; // ISO 8601
  }>;

  // Mood stability metrics (from daily_signals.mood_variance)
  moodVariance?: number; // Variance in mood throughout day (lower = more stable)

  // Quest data (from quests table)
  questCompleted: boolean;

  // Social data (from circle_posts table)
  circleCheckins: number;

  // Exercise data (from exercise_sessions table)
  exerciseMinutes: number;

  // App engagement metrics (from daily_signals)
  appSessions?: number; // Number of app opens
  totalActiveMinutes?: number; // Time actively using app

  // Biometric data (from HealthKit via biometric_daily_summaries)
  sleepHours?: number; // Optional - may not be available
  sleepQuality?: number; // 0-100 quality score from HealthKit
  activitySteps?: number; // Optional - may not be available
  exerciseMinutesFromBiometrics?: number; // Workout minutes from HealthKit
  
  // Advanced biometrics (stress & recovery indicators)
  hrvAverageMs?: number; // Heart rate variability (higher = better stress resilience)
  restingHeartRate?: number; // BPM (lower typically = better cardiovascular health)
}

export interface ScoreComponent {
  value: number; // 0-100 raw score before weighting
  weight: number; // 0.0-1.0 component weight
  confidence: number; // 0-100 confidence level
  reason: string; // Human-readable explanation
}

export interface WellnessScoreOutput {
  score: number; // 0-100 overall wellness score
  confidence: number; // 0-100 overall confidence
  components: {
    // Emotional Health (40% total)
    mood: ScoreComponent; // 15%
    anxiety: ScoreComponent; // 10%
    energy: ScoreComponent; // 10%
    emotional_stability: ScoreComponent; // 5%
    
    // Behavioral Engagement (30% total)
    quest: ScoreComponent; // 15%
    social: ScoreComponent; // 7.5%
    exercises: ScoreComponent; // 7.5%
    
    // Physical Health (30% total)
    sleep: ScoreComponent; // 12%
    activity: ScoreComponent; // 10%
    stress_resilience: ScoreComponent; // 8% (HRV + RHR)
  };
}

// Database schema match (daily_signals.wellness_components column)
export interface WellnessComponentsDB {
  mood: ComponentDB;
  quest: ComponentDB;
  social: ComponentDB;
  activity: ComponentDB;
  sleep: ComponentDB;
}

interface ComponentDB {
  value: number;
  weight: number;
  confidence: number;
  reason: string;
}
