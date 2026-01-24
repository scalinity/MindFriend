// N006: Wellbeing Debt Calculator - Shared TypeScript Types
// Used by: detect-transactions, calculate-debt-score, generate-recovery-program

export interface Transaction {
  id?: string;
  user_id: string;
  date: string; // ISO date (YYYY-MM-DD)
  type: "deposit" | "withdrawal";
  category: TransactionCategory;
  amount: number;
  source: TransactionSource;
  description?: string;
  metadata?: Record<string, any>;
  created_at?: string;
}

export type TransactionCategory =
  // Deposits
  | "sleep_quality"
  | "exercise_completion"
  | "social_connection"
  | "meditation"
  | "outdoor_time"
  | "quest_completion"
  | "positive_event"
  // Withdrawals
  | "poor_sleep"
  | "missed_sleep"
  | "work_stress"
  | "conflict"
  | "social_isolation"
  | "negative_mood"
  | "health_issue"
  | "circadian_disruption";

export type TransactionSource =
  | "healthkit"
  | "mood_log"
  | "exercise_sessions"
  | "circle_posts"
  | "quests"
  | "circadian_shield"
  | "user_logged"
  | "inferred";

export interface DebtScore {
  id?: string;
  user_id: string;
  date: string;
  daily_balance: number;
  rolling_debt_7day: number;
  rolling_debt_14day: number;
  rolling_debt_30day: number;
  trend: TrendData;
  threshold_status: ThresholdStatus;
  created_at?: string;
}

export interface TrendData {
  direction: "improving" | "worsening" | "stable";
  velocity: number; // Points per day (negative = worsening)
  projection_7day: number; // Projected debt in 7 days
}

export interface ThresholdStatus {
  current_debt: number;
  threshold: number | null;
  severity: "safe" | "warning" | "danger";
  days_until_crash: number | null;
  confidence: number; // 0-1 scale
}

export interface UserProfile {
  id?: string;
  user_id: string;
  personal_threshold: number | null;
  crash_history: CrashHistory;
  top_drains: TopCategories;
  top_deposits: TopCategories;
  updated_at?: string;
}

export interface CrashHistory {
  crashes: CrashEvent[];
  last_updated: string | null;
}

export interface CrashEvent {
  date: string;
  debt_at_crash: number;
  mood_score: number;
}

export interface TopCategories {
  categories: CategoryStats[];
  last_updated: string | null;
}

export interface CategoryStats {
  category: string;
  total_amount: number;
  frequency: number;
}

export interface RecoveryProgram {
  user_id: string;
  generated_at: string;
  target_debt_reduction: number;
  daily_actions: DailyActions[];
}

export interface DailyActions {
  day: number;
  date: string;
  focus_area: string;
  actions: RecoveryAction[];
}

export interface RecoveryAction {
  category: TransactionCategory;
  action: string;
  target_points: number;
  source: TransactionSource;
}

// HealthKit sleep data structure (from iOS sync)
export interface HealthKitSleepData {
  user_id: string;
  date: string;
  total_sleep_seconds: number;
  deep_sleep_seconds: number | null; // iOS 16+ only
  rem_sleep_seconds: number | null; // iOS 16+ only
  awake_time_seconds: number | null;
  quality: number | null; // 0-1 scale (calculated)
}

// Mood data structure
export interface MoodEntry {
  user_id: string;
  mood_score: number; // 1-10 scale (MindFriend standard)
  created_at: string;
}

// Exercise session data structure
export interface ExerciseSession {
  id: string;
  user_id: string;
  exercise_id: string;
  completed_at: string;
  duration_seconds: number;
}

// Circle post data structure
export interface CirclePost {
  id: string;
  user_id: string;
  circle_id: string;
  content: string;
  created_at: string;
}

// Quest data structure
export interface Quest {
  id: string;
  user_id: string;
  date: string;
  status: "pending" | "completed" | "missed";
  completed_at: string | null;
}

// Circadian rhythm data (from N002)
export interface CircadianData {
  user_id: string;
  date: string;
  social_jetlag_minutes: number;
  chronotype: string | null;
}
