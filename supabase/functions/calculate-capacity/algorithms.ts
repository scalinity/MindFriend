import type {
  CapacityInput,
  CapacityResult,
  CapacityLevel,
  MoodData,
  SleepData,
  StreakData,
} from "./types.ts";

// =====================================================
// CONFIGURATION CONSTANTS
// =====================================================

// Weight configuration aligned with spec
export const WEIGHTS = {
  sleep: 0.3, // 30% (was 35%)
  mood: 0.35, // 35% (was 40%)
  streak: 0.2, // 20% (was 25%)
  completion: 0.15, // 15% (was missing)
} as const;

// Smoothing factor for exponential moving average
const SMOOTHING_FACTOR = 0.3; // 30% today, 70% previous

// Completion volume scaling factor
const COMPLETION_VOLUME_DIVISOR = 30; // Target: 30 completed quests for max volume score

// Sleep scoring constants
const SLEEP_OPTIMAL_MIN_HOURS = 7; // Minimum hours for optimal sleep
const SLEEP_OPTIMAL_MAX_HOURS = 9; // Maximum hours for optimal sleep
const SLEEP_GOOD_MIN_HOURS = 6; // Minimum hours for good sleep
const SLEEP_POOR_MIN_HOURS = 5; // Minimum hours for poor sleep

const SLEEP_SCORE_OPTIMAL = 100; // Score for optimal sleep (7-9 hours)
const SLEEP_SCORE_GOOD = 70; // Score for good sleep (6-7 hours)
const SLEEP_SCORE_POOR = 40; // Score for poor sleep (5-6 hours)
const SLEEP_SCORE_VERY_POOR = 20; // Score for very poor sleep (<5 hours)

const SLEEP_FALLBACK_OPTIMAL_SCORE = 80; // Fallback score when using average instead of last night
const SLEEP_FALLBACK_GOOD_SCORE = 60;
const SLEEP_FALLBACK_POOR_SCORE = 30;

const SLEEP_BASELINE_SCORE = 50; // Baseline score when no data available
const SLEEP_DEFICIT_PENALTY_MAX = 20; // Maximum penalty for accumulated sleep deficit
const SLEEP_DEFICIT_PENALTY_MULTIPLIER = 2; // Penalty multiplier per hour of deficit
const SLEEP_TARGET_HOURS = 7; // Target sleep hours for deficit calculation

// Mood scoring constants
const MOOD_BASELINE_SCORE = 50; // Baseline score when no data available
const MOOD_SCALE_MAX = 10; // Maximum mood score (1-10 scale)
const MOOD_TREND_ADJUSTMENT_MAX = 15; // Maximum trend adjustment (±15 points)
const MOOD_TREND_MULTIPLIER = 10; // Multiplier for trend adjustment

// Streak scoring constants
const STREAK_BASE_SCORE = 20; // Base score for streaks
const STREAK_GROWTH_MULTIPLIER = 15; // Logarithmic growth multiplier
const STREAK_COMPLETION_BONUS = 10; // Bonus for completing today's quest

// Completion scoring constants
const COMPLETION_RATE_WEIGHT = 0.7; // Weight for recent completion rate (70%)
const COMPLETION_VOLUME_WEIGHT = 0.3; // Weight for total volume (30%)

// Capacity level thresholds
const CAPACITY_THRESHOLD_LOW = 35; // Below this is "low" capacity
const CAPACITY_THRESHOLD_MODERATE = 70; // Below this is "moderate", above is "high"

// Score bounds
const SCORE_MIN = 0;
const SCORE_MAX = 100;

/**
 * Validate numeric value is safe for calculations
 * @param value Value to validate
 * @returns true if value is a finite number
 */
function isValidNumber(value: number | null | undefined): value is number {
  return value !== null && value !== undefined && Number.isFinite(value);
}

/**
 * Validate sleep hours are in realistic range
 * @param hours Sleep hours to validate
 * @returns true if hours are in valid range (0-24)
 */
function isValidSleepHours(hours: number): boolean {
  return hours >= 0 && hours <= 24;
}

/**
 * Calculate sleep component score (0-100)
 * FIXED: Added comprehensive null/NaN/Infinity validation and range checks
 */
export function calculateSleepScore(sleepData: SleepData[]): number {
  if (sleepData.length === 0) {
    return SLEEP_BASELINE_SCORE;
  }

  const data = sleepData[0];
  let score = SLEEP_BASELINE_SCORE;

  // Primary factor: last night's sleep
  if (
    isValidNumber(data.lastNightHours) &&
    isValidSleepHours(data.lastNightHours)
  ) {
    if (
      data.lastNightHours >= SLEEP_OPTIMAL_MIN_HOURS &&
      data.lastNightHours <= SLEEP_OPTIMAL_MAX_HOURS
    ) {
      score = SLEEP_SCORE_OPTIMAL;
    } else if (data.lastNightHours >= SLEEP_GOOD_MIN_HOURS) {
      score = SLEEP_SCORE_GOOD;
    } else if (data.lastNightHours >= SLEEP_POOR_MIN_HOURS) {
      score = SLEEP_SCORE_POOR;
    } else {
      score = SLEEP_SCORE_VERY_POOR;
    }
  } else if (
    isValidNumber(data.averageHours) &&
    isValidSleepHours(data.averageHours)
  ) {
    // Fall back to average if last night unavailable or invalid
    if (
      data.averageHours >= SLEEP_OPTIMAL_MIN_HOURS &&
      data.averageHours <= SLEEP_OPTIMAL_MAX_HOURS
    ) {
      score = SLEEP_FALLBACK_OPTIMAL_SCORE;
    } else if (data.averageHours >= SLEEP_GOOD_MIN_HOURS) {
      score = SLEEP_FALLBACK_GOOD_SCORE;
    } else {
      score = SLEEP_FALLBACK_POOR_SCORE;
    }
  }
  // If both are invalid, keep baseline score

  // Factor in quality if available (quality is 0-100)
  if (isValidNumber(data.quality) && data.quality >= 0 && data.quality <= 100) {
    score = (score + data.quality) / 2;
  }

  // Penalize for accumulated deficit (capped at max penalty)
  if (isValidNumber(data.deficit7d) && data.deficit7d > 0) {
    const penalty = Math.min(
      SLEEP_DEFICIT_PENALTY_MAX,
      data.deficit7d * SLEEP_DEFICIT_PENALTY_MULTIPLIER,
    );
    score -= penalty;
  }

  return clamp(score, SCORE_MIN, SCORE_MAX);
}

/**
 * Calculate mood component score (0-100)
 * FIXED: Added comprehensive null/NaN/Infinity validation and range checks
 */
export function calculateMoodScore(moodData: MoodData[]): number {
  if (moodData.length === 0) {
    return MOOD_BASELINE_SCORE;
  }

  const data = moodData[0];
  let score = MOOD_BASELINE_SCORE;

  // Convert mood (1-10) to score (0-100)
  if (
    isValidNumber(data.todayMood) &&
    data.todayMood >= 1 &&
    data.todayMood <= MOOD_SCALE_MAX
  ) {
    score = (data.todayMood / MOOD_SCALE_MAX) * SCORE_MAX;
  } else if (
    isValidNumber(data.averageMood3d) &&
    data.averageMood3d >= 1 &&
    data.averageMood3d <= MOOD_SCALE_MAX
  ) {
    // Fall back to 3-day average if today's mood is invalid
    score = (data.averageMood3d / MOOD_SCALE_MAX) * SCORE_MAX;
  }
  // If both are invalid, keep baseline score

  // Adjust for trend (capped at ±max adjustment)
  if (isValidNumber(data.trend3d) && data.trend3d !== 0) {
    const trendAdjustment = clamp(
      data.trend3d * MOOD_TREND_MULTIPLIER,
      -MOOD_TREND_ADJUSTMENT_MAX,
      MOOD_TREND_ADJUSTMENT_MAX,
    );
    score += trendAdjustment;
  }

  return clamp(score, SCORE_MIN, SCORE_MAX);
}

/**
 * Calculate streak component score (0-100)
 */
export function calculateStreakScore(streakData: StreakData): number {
  const { current_streak = 0, longest_streak = 0 } = streakData;

  // SAFETY: Ensure streak days is non-negative (prevent -Infinity from log2)
  const safeStreakDays = Math.max(0, streakData.streakDays);

  // Logarithmic growth: base score + log scale
  // 0 days → base score
  // 1 day → base + log2(2)*multiplier
  // 7 days → base + log2(8)*multiplier
  // 14 days → base + log2(15)*multiplier
  // 30 days → base + log2(31)*multiplier
  let score =
    STREAK_BASE_SCORE +
    Math.log2(safeStreakDays + 1) * STREAK_GROWTH_MULTIPLIER;

  // Boost if already completed today
  if (streakData.completedToday) {
    score += STREAK_COMPLETION_BONUS;
  }

  return clamp(score, SCORE_MIN, SCORE_MAX);
}

/**
 * Calculate completion component score (0-100)
 * NEW: Added completion component per spec
 */
export function calculateCompletionScore(
  recentCompletionRate: number,
  questsCompleted: number,
): number {
  // Recent completion rate (0-1) contributes rate weight %
  const rateScore = Math.min(recentCompletionRate * SCORE_MAX, SCORE_MAX);

  // Total quests completed contributes volume weight % (diminishing returns)
  const volumeScore = Math.min(
    (questsCompleted / COMPLETION_VOLUME_DIVISOR) * SCORE_MAX,
    SCORE_MAX,
  );

  return Math.round(
    rateScore * COMPLETION_RATE_WEIGHT + volumeScore * COMPLETION_VOLUME_WEIGHT,
  );
}

/**
 * Calculate composite capacity score from all components
 */
export function calculateCompositeScore(components: {
  sleep: number;
  mood: number;
  streak: number;
  completion: number;
}): number {
  // SAFETY: Validate all components are finite numbers
  const validatedComponents = {
    sleep: isValidNumber(components.sleep) ? components.sleep : 50,
    mood: isValidNumber(components.mood) ? components.mood : 50,
    streak: isValidNumber(components.streak) ? components.streak : 50,
    completion: isValidNumber(components.completion)
      ? components.completion
      : 50,
  };

  const rawScore =
    validatedComponents.sleep * WEIGHTS.sleep +
    validatedComponents.mood * WEIGHTS.mood +
    validatedComponents.streak * WEIGHTS.streak +
    validatedComponents.completion * WEIGHTS.completion;

  // SAFETY: Validate result before return
  if (!isValidNumber(rawScore)) {
    console.error("Composite score calculation produced invalid result", {
      components: validatedComponents,
      rawScore,
    });
    return 50; // Fallback to moderate baseline
  }

  return Math.round(Math.max(SCORE_MIN, Math.min(SCORE_MAX, rawScore)));
}

/**
 * Map score to capacity level
 * UPDATED: Thresholds aligned with spec (0-35 low, 35-70 moderate, 70-100 high)
 */
export function scoreToLevel(score: number): CapacityLevel {
  if (score < CAPACITY_THRESHOLD_LOW) return "low";
  if (score < CAPACITY_THRESHOLD_MODERATE) return "moderate";
  return "high";
}

/**
 * Apply smoothing to capacity score using exponential moving average
 * @param rawScore Current raw capacity score
 * @param previousScore Previous capacity score (null for first calculation)
 * @returns Smoothed capacity score
 */
export function smoothCapacity(
  rawScore: number,
  previousScore: number | null,
): number {
  // SAFETY: Validate rawScore is finite
  if (!isValidNumber(rawScore)) {
    console.error("smoothCapacity called with invalid rawScore:", rawScore);
    return 50; // Fallback to moderate baseline
  }

  // SAFETY: Validate previousScore if provided
  if (previousScore !== null && !isValidNumber(previousScore)) {
    console.warn(
      "Invalid previousScore, treating as first calculation:",
      previousScore,
    );
    previousScore = null;
  }

  if (previousScore === null) {
    return rawScore; // First calculation, no smoothing
  }

  // Exponential moving average: new = previous * (1 - α) + current * α
  const smoothed =
    previousScore * (1 - SMOOTHING_FACTOR) + rawScore * SMOOTHING_FACTOR;

  // SAFETY: Validate result
  if (!isValidNumber(smoothed)) {
    console.error("Smoothing produced invalid result, using raw score", {
      rawScore,
      previousScore,
      smoothed,
    });
    return rawScore;
  }

  return Math.round(smoothed);
}

/**
 * Main capacity calculation function
 * BUG FIX: Now includes completion component and uses calculateCompositeScore()
 * @param input Capacity input data
 * @returns Capacity result
 */
export function calculateCapacity(input: CapacityInput): CapacityResult {
  // Calculate component scores
  const sleepScore = calculateSleepScore(input.sleep ? [input.sleep] : []);
  const moodScore = calculateMoodScore(input.mood ? [input.mood] : []);
  const streakScore = calculateStreakScore(input.streak);
  const completionScore = calculateCompletionScore(
    input.completion.recentCompletionRate,
    input.completion.questsCompleted,
  );

  // Calculate composite score with all 4 components
  const rawScore = calculateCompositeScore({
    sleep: sleepScore,
    mood: moodScore,
    streak: streakScore,
    completion: completionScore,
  });

  // Apply smoothing
  const finalScore = smoothCapacity(rawScore, input.previous);

  // Determine level
  const level = scoreToLevel(finalScore);

  return {
    score: Math.round(finalScore),
    level,
    components: {
      sleep: Math.round(sleepScore),
      mood: Math.round(moodScore),
      streak: Math.round(streakScore),
      completion: Math.round(completionScore),
    },
  };
}

/**
 * Utility: Clamp value between min and max
 * @param value Value to clamp
 * @param min Minimum value
 * @param max Maximum value
 * @returns Clamped value
 */
function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
