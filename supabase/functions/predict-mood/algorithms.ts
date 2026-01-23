// Mood Prediction Algorithms
// Weighted regression model for mood prediction with confidence scoring

import type {
  PredictionFeatures,
  FeatureWeights,
  ContributingFactor,
  PredictionResult,
} from "./types.ts";

// Default feature weights (used when no user-specific model exists)
export const DEFAULT_WEIGHTS: FeatureWeights = {
  sleep_hours: 0.25,
  steps_yesterday: 0.15,
  mood_avg_7d: 0.3,
  mood_trend_7d: 0.15,
  day_of_week: 0.1,
  exercise_minutes: 0.05,
};

// Day of week factors (relative impact on mood)
// Based on research: Monday blues, Friday boost, weekend mixed
const DAY_OF_WEEK_FACTORS: Record<number, { factor: number; name: string }> = {
  0: { factor: -0.1, name: "Sunday" }, // Sunday scaries
  1: { factor: -0.3, name: "Monday" }, // Monday blues
  2: { factor: -0.1, name: "Tuesday" },
  3: { factor: 0.0, name: "Wednesday" },
  4: { factor: 0.1, name: "Thursday" },
  5: { factor: 0.3, name: "Friday" }, // Friday boost
  6: { factor: 0.1, name: "Saturday" },
};

// Normalization constants (based on typical ranges)
const SLEEP_HOURS_TARGET = 7.5;
const SLEEP_HOURS_MAX_IMPACT = 2.0; // Max mood points from sleep
const STEPS_TARGET = 8000;
const STEPS_MAX_IMPACT = 1.0; // Max mood points from steps
const EXERCISE_TARGET_MINUTES = 150; // Weekly target
const EXERCISE_MAX_IMPACT = 0.5;
const TREND_MAX_IMPACT = 1.5; // Max impact from 7-day trend

/**
 * Calculate mood prediction using weighted regression
 */
export function calculatePrediction(
  features: PredictionFeatures,
  weights: FeatureWeights = DEFAULT_WEIGHTS,
): PredictionResult {
  const factors: ContributingFactor[] = [];

  // Base mood from 7-day average (scale from 1-5 to 1-10)
  const baseMood = features.mood_avg_7d * 2;

  let totalImpact = 0;

  // 1. Sleep impact
  if (features.has_sleep_data && features.sleep_hours !== null) {
    const sleepDelta = features.sleep_hours - SLEEP_HOURS_TARGET;
    // Negative impact if under target, positive if over (with diminishing returns)
    const sleepImpact = Math.max(
      -SLEEP_HOURS_MAX_IMPACT,
      Math.min(SLEEP_HOURS_MAX_IMPACT, sleepDelta * 0.4),
    );

    totalImpact += sleepImpact * weights.sleep_hours;

    if (Math.abs(sleepImpact) > 0.2) {
      factors.push({
        factor: "sleep_hours",
        impact: sleepImpact,
        description:
          sleepDelta < 0
            ? `Only ${features.sleep_hours.toFixed(1)}h sleep last night (${Math.abs(sleepDelta).toFixed(1)}h below target)`
            : `Good sleep: ${features.sleep_hours.toFixed(1)}h last night`,
      });
    }
  }

  // 2. Steps impact
  if (features.has_steps_data && features.steps_yesterday !== null) {
    const stepsRatio = features.steps_yesterday / STEPS_TARGET;
    const stepsImpact = Math.max(
      -STEPS_MAX_IMPACT,
      Math.min(STEPS_MAX_IMPACT, (stepsRatio - 1) * 0.5),
    );

    totalImpact += stepsImpact * weights.steps_yesterday;

    if (Math.abs(stepsImpact) > 0.2) {
      factors.push({
        factor: "steps_yesterday",
        impact: stepsImpact,
        description:
          stepsRatio < 0.5
            ? `Low activity yesterday: ${features.steps_yesterday.toLocaleString()} steps`
            : stepsRatio > 1.2
              ? `Great activity: ${features.steps_yesterday.toLocaleString()} steps yesterday`
              : `${features.steps_yesterday.toLocaleString()} steps yesterday`,
      });
    }
  }

  // 3. Mood trend impact
  const trendImpact = Math.max(
    -TREND_MAX_IMPACT,
    Math.min(TREND_MAX_IMPACT, features.mood_trend_7d),
  );

  totalImpact += trendImpact * weights.mood_trend_7d;

  if (Math.abs(trendImpact) > 0.3) {
    factors.push({
      factor: "mood_trend",
      impact: trendImpact,
      description:
        trendImpact < 0
          ? "Your mood has been trending down this week"
          : "Your mood has been improving this week",
    });
  }

  // 4. Day of week impact
  const dayInfo = DAY_OF_WEEK_FACTORS[features.day_of_week] || {
    factor: 0,
    name: "Unknown",
  };
  const dayImpact = dayInfo.factor;

  totalImpact += dayImpact * weights.day_of_week;

  if (Math.abs(dayImpact) >= 0.2) {
    factors.push({
      factor: "day_of_week",
      impact: dayImpact,
      description:
        dayImpact < 0
          ? `${dayInfo.name}s tend to be harder for you`
          : `${dayInfo.name}s are usually better for you`,
    });
  }

  // 5. Exercise impact
  const exerciseRatio = features.exercise_minutes_7d / EXERCISE_TARGET_MINUTES;
  const exerciseImpact = Math.max(
    -EXERCISE_MAX_IMPACT,
    Math.min(EXERCISE_MAX_IMPACT, (exerciseRatio - 0.5) * 0.3),
  );

  totalImpact += exerciseImpact * weights.exercise_minutes;

  if (exerciseImpact > 0.2) {
    factors.push({
      factor: "exercise",
      impact: exerciseImpact,
      description: `Active week: ${features.exercise_minutes_7d} min of exercise`,
    });
  }

  // 6. Streak boost
  if (features.streak_days > 0) {
    const streakBoost = Math.min(0.5, features.streak_days * 0.03);
    totalImpact += streakBoost;

    if (features.streak_days >= 7) {
      factors.push({
        factor: "streak",
        impact: streakBoost,
        description: `${features.streak_days}-day streak is providing stability`,
      });
    }
  }

  // Calculate final predicted mood (clamped to 1-10)
  const predictedMood = Math.max(1, Math.min(10, baseMood + totalImpact));

  // Calculate confidence
  const confidence = calculateConfidence(features, weights);

  // Sort factors by absolute impact (most impactful first)
  factors.sort((a, b) => Math.abs(b.impact) - Math.abs(a.impact));

  // Keep top 5 factors
  const topFactors = factors.slice(0, 5);

  return {
    predictedMood: Math.round(predictedMood * 10) / 10, // Round to 1 decimal
    confidence: Math.round(confidence * 100) / 100, // Round to 2 decimals
    factors: topFactors,
    modelVersion: "v1.0-regression",
    featuresUsed: {
      mood_avg_7d: features.mood_avg_7d,
      mood_trend_7d: features.mood_trend_7d,
      sleep_hours: features.sleep_hours,
      steps_yesterday: features.steps_yesterday,
      day_of_week: features.day_of_week,
      exercise_minutes_7d: features.exercise_minutes_7d,
      streak_days: features.streak_days,
    },
  };
}

/**
 * Calculate prediction confidence based on data availability and quality
 */
export function calculateConfidence(
  features: PredictionFeatures,
  _weights: FeatureWeights = DEFAULT_WEIGHTS,
): number {
  let score = 0.4; // Base confidence

  // Core data availability (mood history is required, so start at 0.4)

  // Biometric data boosts confidence
  if (features.has_sleep_data) {
    score += 0.15;
  }
  if (features.has_steps_data) {
    score += 0.1;
  }

  // Exercise data adds confidence
  if (features.exercise_minutes_7d > 0) {
    score += 0.05;
  }

  // Streak indicates engaged user with reliable data
  if (features.streak_days >= 7) {
    score += 0.1;
  } else if (features.streak_days >= 3) {
    score += 0.05;
  }

  // Recent mood data is more reliable
  // (Previous mood within 24h adds confidence)
  score += 0.15; // Assume we have recent mood if eligible

  // Cap at 0.95 (never fully confident)
  return Math.min(0.95, score);
}

/**
 * Determine if an intervention should be triggered
 */
export function shouldTriggerIntervention(
  predictedMood: number,
  confidence: number,
): boolean {
  // Trigger intervention if:
  // 1. Predicted mood is low (< 4 on 1-10 scale, which is < 2 on 1-5 scale)
  // 2. Confidence is sufficient (> 0.6)
  return predictedMood < 4 && confidence > 0.6;
}
