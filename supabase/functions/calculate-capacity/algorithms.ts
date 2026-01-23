import type {
  CapacityInput,
  CapacityResult,
  MoodData,
  SleepData,
  StreakData,
} from "./types.ts";

// Weight configuration aligned with spec
const WEIGHTS = {
  sleep: 0.30,      // 30% (was 35%)
  mood: 0.35,       // 35% (was 40%)
  streak: 0.20,     // 20% (was 25%)
  completion: 0.15, // 15% (was missing)
} as const;

// Smoothing factor for exponential moving average
const SMOOTHING_FACTOR = 0.3; // 30% today, 70% previous

// Capacity level thresholds
const LEVEL_THRESHOLDS = {
  low: 40, // 0-40 = low
  moderate: 70, // 41-70 = moderate
  // 71-100 = high
} as const;

/**
 * Calculate sleep component score (0-100)
 * BUG FIX: Added division by zero protection
 */
export function calculateSleepScore(sleepData: SleepData[]): number {
  if (sleepData.length === 0) {
    return 50; // Default neutral score when no data
  }

  const avgQuality =
    sleepData.reduce((sum, s) => sum + (s.quality_score || 0), 0) / sleepData.length;

  let score = 50; // Baseline

  // Primary factor: last night's sleep
  if (sleepData[0].lastNightHours !== null) {
    if (sleepData[0].lastNightHours >= 7 && sleepData[0].lastNightHours <= 9) {
      score = 100; // Optimal sleep
    } else if (sleepData[0].lastNightHours >= 6) {
      score = 70; // Good sleep
    } else if (sleepData[0].lastNightHours >= 5) {
      score = 40; // Poor sleep
    } else {
      score = 20; // Very poor sleep
    }
  } else {
    // Fall back to average if last night unavailable
    if (sleepData[0].averageHours >= 7 && sleepData[0].averageHours <= 9) {
      score = 80;
    } else if (sleepData[0].averageHours >= 6) {
      score = 60;
    } else {
      score = 30;
    }
  }

  // Factor in quality if available
  if (sleepData[0].quality !== null) {
    score = (score + sleepData[0].quality) / 2;
  }

  // Penalize for accumulated deficit (capped at -20 points)
  if (sleepData[0].deficit7d > 0) {
    const penalty = Math.min(20, sleepData[0].deficit7d * 2);
    score -= penalty;
  }

  return clamp(score, 0, 100);
}

/**
 * Calculate mood component score (0-100)
 * BUG FIX: Added division by zero protection
 */
export function calculateMoodScore(moodData: MoodData[]): number {
  if (moodData.length === 0) {
    return 50; // Default neutral score when no data
  }

  const avgValence =
    moodData.reduce((sum, m) => sum + (m.valence || 0), 0) / moodData.length;

  // Convert mood (1-10) to score (0-100)
  let score = 50;

  if (moodData[0].todayMood !== null) {
    score = (moodData[0].todayMood / 10) * 100;
  } else {
    // Fall back to 3-day average
    score = (moodData[0].averageMood3d / 10) * 100;
  }

  // Adjust for trend (capped at ±15 points)
  if (moodData[0].trend3d !== 0) {
    const trendAdjustment = clamp(moodData[0].trend3d * 10, -15, 15);
    score += trendAdjustment;
  }

  return clamp(score, 0, 100);
}

/**
 * Calculate streak component score (0-100)
 */
export function calculateStreakScore(streakData: StreakData): number {
  const { current_streak = 0, longest_streak = 0 } = streakData;

  // Logarithmic growth: base 20 + log scale
  // 0 days → 20
  // 1 day → 20 + log2(2)*15 ≈ 35
  // 7 days → 20 + log2(8)*15 ≈ 65
  // 14 days → 20 + log2(15)*15 ≈ 78
  // 30 days → 20 + log2(31)*15 ≈ 95
  let score = 20 + Math.log2(streakData.streakDays + 1) * 15;

  // Boost if already completed today
  if (streakData.completedToday) {
    score += 10;
  }

  return clamp(score, 0, 100);
}

/**
 * Calculate completion component score (0-100)
 * NEW: Added completion component per spec
 */
export function calculateCompletionScore(
  recentCompletionRate: number,
  questsCompleted: number,
): number {
  // Recent completion rate (0-1) contributes 70%
  const rateScore = Math.min(recentCompletionRate * 100, 100);
  
  // Total quests completed contributes 30% (diminishing returns)
  const volumeScore = Math.min((questsCompleted / 30) * 100, 100);
  
  return Math.round(rateScore * 0.7 + volumeScore * 0.3);
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
  const rawScore =
    components.sleep * WEIGHTS.sleep +
    components.mood * WEIGHTS.mood +
    components.streak * WEIGHTS.streak +
    components.completion * WEIGHTS.completion;

  return Math.round(Math.max(0, Math.min(100, rawScore)));
}

/**
 * Map score to capacity level
 * UPDATED: Thresholds aligned with spec (0-35 low, 35-70 moderate, 70-100 high)
 */
export function scoreToLevel(score: number): CapacityLevel {
  if (score < 35) return "low";
  if (score < 70) return "moderate";
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
  if (previousScore === null) {
    return rawScore; // First calculation, no smoothing
  }

  // Exponential moving average: new = previous * (1 - α) + current * α
  const smoothed =
    previousScore * (1 - SMOOTHING_FACTOR) + rawScore * SMOOTHING_FACTOR;

  return Math.round(smoothed);
}

/**
 * Convert capacity score to level
 * @param score Capacity score (0-100)
 * @returns Capacity level
 */
export function getCapacityLevel(score: number): "low" | "moderate" | "high" {
  if (score <= LEVEL_THRESHOLDS.low) {
    return "low";
  } else if (score <= LEVEL_THRESHOLDS.moderate) {
    return "moderate";
  } else {
    return "high";
  }
}

/**
 * Main capacity calculation function
 * @param input Capacity input data
 * @returns Capacity result
 */
export function calculateCapacity(input: CapacityInput): CapacityResult {
  // Calculate component scores
  const sleepScore = calculateSleepScore(input.sleep);
  const moodScore = calculateMoodScore(input.mood);
  const streakScore = calculateStreakScore(input.streak);

  // Weighted average
  const rawScore =
    sleepScore * WEIGHTS.sleep +
    moodScore * WEIGHTS.mood +
    streakScore * WEIGHTS.streak;

  // Apply smoothing
  const finalScore = smoothCapacity(rawScore, input.previous);

  // Determine level
  const level = getCapacityLevel(finalScore);

  return {
    score: Math.round(finalScore),
    level,
    components: {
      sleep: Math.round(sleepScore),
      mood: Math.round(moodScore),
      streak: Math.round(streakScore),
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
