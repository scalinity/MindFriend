// Types for capacity calculation Edge Function

export interface CalculateCapacityRequest {
  localDate: string; // YYYY-MM-DD
  timezone: string; // e.g., "America/Los_Angeles"
}

export interface CalculateCapacityResponse {
  score: number; // 0-100
  level: "low" | "moderate" | "high";
  components: {
    sleep: ComponentScore;
    mood: ComponentScore;
    streak: ComponentScore;
  };
  calculated_at: string; // ISO 8601
  expires_at: string; // ISO 8601
  has_override: boolean;
}

export interface ComponentScore {
  score: number; // 0-100
  weight: number; // 0.0-1.0
  contribution: number; // weighted score
}

export interface CapacityInput {
  sleep: SleepData | null;
  mood: MoodData | null;
  streak: StreakData;
  previous: number | null; // Previous capacity score for smoothing
}

export interface SleepData {
  quality_score: number | null;
  lastNightHours: number | null;
  averageHours: number;
  quality: number | null;
  deficit7d: number;
}

export interface MoodData {
  valence: number | null;
  todayMood: number | null;
  averageMood3d: number;
  trend3d: number;
}

export interface StreakData {
  current_streak: number;
  longest_streak: number;
  streakDays: number;
  completedToday: boolean;
}

export interface CompletionData {
  recentCompletionRate: number; // 0-1
  questsCompleted: number;
}

export interface CapacityComponents {
  sleep: number;
  mood: number;
  streak: number;
  completion: number;
}

export interface CapacityResult {
  score: number;
  level: "low" | "moderate" | "high";
  components: {
    sleep: number;
    mood: number;
    streak: number;
  };
}

// Database types
export interface UserCapacityRow {
  id: string;
  user_id: string;
  score: number;
  level: string;
  components: Record<string, unknown>;
  local_date: string;
  calculated_at: string;
  expires_at: string;
  has_override: boolean;
  previous_score: number | null;
}

export interface CapacityOverrideRow {
  id: string;
  user_id: string;
  override_level: "rest" | "normal" | "challenge";
  created_at: string;
  expires_at: string;
  is_active: boolean;
}

export interface Mood {
  id: string;
  user_id: string;
  mood_score: number; // 1-10
  logged_at: string;
}

export interface SleepLog {
  id: string;
  user_id: string;
  fell_asleep_at: string;
  woke_up_at: string;
  quality_score?: number; // 0-100
  logged_at: string;
}
