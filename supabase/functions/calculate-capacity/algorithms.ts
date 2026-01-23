import type {
  CapacityInput,
  CapacityResult,
  MoodData,
  SleepData,
  StreakData,
} from "./types.ts";

// Weights for capacity components (must sum to 1.0)
const WEIGHTS = {
  sleep: 0.35, // 35%
  mood: 0.4, // 40%
  streak: 0.25, // 25%
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
 * @param sleep Sleep data from last 7 days
 * @returns Sleep component score
 */
export function calculateSleepScore(sleep: SleepData | null): number {
  if (!sleep) {
    return 50; // Default if no sleep data
  }

  let score = 50; // Baseline

  // Primary factor: last night's sleep
  if (sleep.lastNightHours !== null) {
    if (sleep.lastNightHours >= 7 && sleep.lastNightHours <= 9) {
      score = 100; // Optimal sleep
    } else if (sleep.lastNightHours >= 6) {
      score = 70; // Good sleep
    } else if (sleep.lastNightHours >= 5) {
      score = 40; // Poor sleep
    } else {
      score = 20; // Very poor sleep
    }
  } else {
    // Fall back to average if last night unavailable
    if (sleep.averageHours >= 7 && sleep.averageHours <= 9) {
      score = 80;
    } else if (sleep.averageHours >= 6) {
      score = 60;
    } else {
      score = 30;
    }
  }

  // Factor in quality if available
  if (sleep.quality !== null) {
    score = (score + sleep.quality) / 2;
  }

  // Penalize for accumulated deficit (capped at -20 points)
  if (sleep.deficit7d > 0) {
    const penalty = Math.min(20, sleep.deficit7d * 2);
    score -= penalty;
  }

  return clamp(score, 0, 100);
}

/**
 * Calculate mood component score (0-100)
 * @param mood Mood data from last 3 days
 * @returns Mood component score
 */
export function calculateMoodScore(mood: MoodData | null): number {
  if (!mood) {
    return 50; // Default if no mood data
  }

  // Convert mood (1-10) to score (0-100)
  let score = 50;

  if (mood.todayMood !== null) {
    score = (mood.todayMood / 10) * 100;
  } else {
    // Fall back to 3-day average
    score = (mood.averageMood3d / 10) * 100;
  }

  // Adjust for trend (capped at ±15 points)
  if (mood.trend3d !== 0) {
    const trendAdjustment = clamp(mood.trend3d * 10, -15, 15);
    score += trendAdjustment;
  }

  return clamp(score, 0, 100);
}

/**
 * Calculate streak component score (0-100)
 * @param streak Streak data
 * @returns Streak component score
 */
export function calculateStreakScore(streak: StreakData): number {
  // Logarithmic growth: base 20 + log scale
  // 0 days → 20
  // 1 day → 20 + log2(2)*15 ≈ 35
  // 7 days → 20 + log2(8)*15 ≈ 65
  // 14 days → 20 + log2(15)*15 ≈ 78
  // 30 days → 20 + log2(31)*15 ≈ 95
  let score = 20 + Math.log2(streak.streakDays + 1) * 15;

  // Boost if already completed today
  if (streak.completedToday) {
    score += 10;
  }

  return clamp(score, 0, 100);
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
