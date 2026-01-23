// Enhanced Wellness Score Calculation Algorithm
// Implements comprehensive 10-component weighted scoring system
// Incorporates mood, anxiety, energy, emotional stability, engagement, sleep, activity, and stress resilience

import type {
  WellnessScoreInput,
  WellnessScoreOutput,
  ScoreComponent,
} from "./types.ts";

/**
 * Calculate comprehensive wellness score from all available daily signals
 *
 * Algorithm weights (total = 100%):
 *
 * EMOTIONAL HEALTH (40%)
 * - Mood: 15% (average mood score 1-10)
 * - Anxiety: 10% (inverted score - lower anxiety = higher score)
 * - Energy: 10% (average energy score 1-10)
 * - Emotional Stability: 5% (low mood variance = stable)
 *
 * BEHAVIORAL ENGAGEMENT (30%)
 * - Quest: 15% (daily quest completion)
 * - Social: 7.5% (circle check-ins)
 * - Exercises: 7.5% (completed wellness exercises)
 *
 * PHYSICAL HEALTH (30%)
 * - Sleep: 12% (duration + quality)
 * - Activity: 10% (steps or exercise minutes)
 * - Stress Resilience: 8% (HRV + resting heart rate)
 *
 * @param input Daily activity data for a user
 * @returns Wellness score (0-100) with 10-component breakdown
 */
export function calculateWellnessScore(
  input: WellnessScoreInput,
): WellnessScoreOutput {
  const components = {
    // Emotional Health (40%)
    mood: calculateMoodScore(input.moods),
    anxiety: calculateAnxietyScore(input.moods),
    energy: calculateEnergyScore(input.moods),
    emotional_stability: calculateEmotionalStabilityScore(input.moodVariance),

    // Behavioral Engagement (30%)
    quest: calculateQuestScore(input.questCompleted),
    social: calculateSocialScore(input.circleCheckins),
    exercises: calculateExercisesScore(input.exerciseMinutes),

    // Physical Health (30%)
    sleep: calculateSleepScore(input.sleepHours, input.sleepQuality),
    activity: calculateActivityScore(
      input.activitySteps,
      input.exerciseMinutesFromBiometrics,
    ),
    stress_resilience: calculateStressResilienceScore(
      input.hrvAverageMs,
      input.restingHeartRate,
    ),
  };

  // Calculate weighted average
  const allComponents = Object.values(components);
  const totalWeight = allComponents.reduce((sum, c) => sum + c.weight, 0);
  const weightedSum = allComponents.reduce(
    (sum, c) => sum + c.value * c.weight,
    0,
  );
  const score = Math.round(weightedSum / totalWeight);

  // Overall confidence = average of component confidences
  const avgConfidence = Math.round(
    allComponents.reduce((sum, c) => sum + c.confidence, 0) /
      allComponents.length,
  );

  return {
    score,
    confidence: avgConfidence,
    components,
  };
}

// ============================================================================
// EMOTIONAL HEALTH COMPONENTS (40% total)
// ============================================================================

/**
 * Mood Score (15% weight)
 *
 * Converts mood scores (1-10) to 0-100 scale.
 * Higher confidence with more mood logs.
 *
 * Scoring:
 * - Mood 1-2 → 0-20 (Very low)
 * - Mood 3-4 → 20-40 (Low)
 * - Mood 5-6 → 40-60 (Neutral)
 * - Mood 7-8 → 60-80 (Good)
 * - Mood 9-10 → 80-100 (Excellent)
 *
 * Confidence:
 * - 0 logs → 0%
 * - 1 log  → 33%
 * - 2 logs → 67%
 * - 3+ logs → 100%
 */
function calculateMoodScore(
  moods: Array<{ moodScore: number }>,
): ScoreComponent {
  if (moods.length === 0) {
    return {
      value: 50, // Neutral default
      weight: 0.15,
      confidence: 0,
      reason: "No mood data today",
    };
  }

  // Average mood score
  const avgMood = moods.reduce((sum, m) => sum + m.moodScore, 0) / moods.length;

  // Map 1-10 to 0-100 (linear scaling)
  const normalized = Math.round(((avgMood - 1) / 9) * 100);

  // Confidence increases with more data points
  const confidence = Math.min(100, Math.round((moods.length / 3) * 100));

  return {
    value: normalized,
    weight: 0.15,
    confidence,
    reason: `Avg mood ${avgMood.toFixed(1)}/10 (${moods.length} log${
      moods.length > 1 ? "s" : ""
    })`,
  };
}

/**
 * Anxiety Score (10% weight)
 *
 * INVERTED scoring: Lower anxiety = higher wellness score
 * Anxiety scale 1-10 where:
 * - 1 = No anxiety (calm)
 * - 10 = Severe anxiety (panicked)
 *
 * Scoring (inverted):
 * - Anxiety 1-2 → Score 90-100 (Very calm)
 * - Anxiety 3-4 → Score 70-90 (Calm)
 * - Anxiety 5-6 → Score 50-70 (Moderate)
 * - Anxiety 7-8 → Score 30-50 (Elevated)
 * - Anxiety 9-10 → Score 0-30 (High anxiety)
 */
function calculateAnxietyScore(
  moods: Array<{ anxietyScore?: number }>,
): ScoreComponent {
  const anxietyLogs = moods.filter((m) => m.anxietyScore !== undefined);

  if (anxietyLogs.length === 0) {
    return {
      value: 70, // Assume moderate-low anxiety when not tracked
      weight: 0.1,
      confidence: 0,
      reason: "No anxiety data tracked",
    };
  }

  const avgAnxiety =
    anxietyLogs.reduce((sum, m) => sum + (m.anxietyScore || 0), 0) /
    anxietyLogs.length;

  // Invert the score: 10 - anxiety gives us reversed scale
  // Then map to 0-100
  const inverted = 11 - avgAnxiety; // 1→10, 10→1
  const normalized = Math.round(((inverted - 1) / 9) * 100);

  const confidence = Math.min(100, Math.round((anxietyLogs.length / 3) * 100));

  return {
    value: normalized,
    weight: 0.1,
    confidence,
    reason: `Anxiety ${avgAnxiety.toFixed(1)}/10 (${anxietyLogs.length} log${
      anxietyLogs.length > 1 ? "s" : ""
    })`,
  };
}

/**
 * Energy Score (10% weight)
 *
 * Direct scoring: Higher energy = higher wellness
 * Energy scale 1-10 where:
 * - 1 = Exhausted
 * - 10 = Highly energized
 *
 * Scoring:
 * - Energy 1-2 → Score 0-20 (Depleted)
 * - Energy 3-4 → Score 20-40 (Low)
 * - Energy 5-6 → Score 40-60 (Moderate)
 * - Energy 7-8 → Score 60-80 (Good)
 * - Energy 9-10 → Score 80-100 (High)
 */
function calculateEnergyScore(
  moods: Array<{ energyScore?: number }>,
): ScoreComponent {
  const energyLogs = moods.filter((m) => m.energyScore !== undefined);

  if (energyLogs.length === 0) {
    return {
      value: 60, // Assume moderate energy when not tracked
      weight: 0.1,
      confidence: 0,
      reason: "No energy data tracked",
    };
  }

  const avgEnergy =
    energyLogs.reduce((sum, m) => sum + (m.energyScore || 0), 0) /
    energyLogs.length;

  // Map 1-10 to 0-100
  const normalized = Math.round(((avgEnergy - 1) / 9) * 100);

  const confidence = Math.min(100, Math.round((energyLogs.length / 3) * 100));

  return {
    value: normalized,
    weight: 0.1,
    confidence,
    reason: `Energy ${avgEnergy.toFixed(1)}/10 (${energyLogs.length} log${
      energyLogs.length > 1 ? "s" : ""
    })`,
  };
}

/**
 * Emotional Stability Score (5% weight)
 *
 * Based on mood variance throughout the day.
 * Lower variance = more stable = better score.
 *
 * Scoring:
 * - Variance 0.0-0.5 → Score 90-100 (Very stable)
 * - Variance 0.5-1.0 → Score 70-90 (Stable)
 * - Variance 1.0-2.0 → Score 50-70 (Moderate)
 * - Variance 2.0-3.0 → Score 30-50 (Unstable)
 * - Variance 3.0+ → Score 0-30 (Very unstable)
 */
function calculateEmotionalStabilityScore(
  moodVariance?: number,
): ScoreComponent {
  if (moodVariance === undefined) {
    return {
      value: 70, // Assume moderate stability when not available
      weight: 0.05,
      confidence: 0,
      reason: "Mood variance not calculated",
    };
  }

  // Invert variance to score (lower variance = higher score)
  let value: number;
  if (moodVariance < 0.5) {
    value = 100;
  } else if (moodVariance < 1.0) {
    value = 90 - Math.round((moodVariance - 0.5) * 40);
  } else if (moodVariance < 2.0) {
    value = 70 - Math.round((moodVariance - 1.0) * 20);
  } else if (moodVariance < 3.0) {
    value = 50 - Math.round((moodVariance - 2.0) * 20);
  } else {
    value = Math.max(0, 30 - Math.round((moodVariance - 3.0) * 10));
  }

  return {
    value,
    weight: 0.05,
    confidence: 100, // High confidence when data available
    reason: `Mood variance ${moodVariance.toFixed(2)} (${
      moodVariance < 1.0 ? "stable" : "fluctuating"
    })`,
  };
}

// ============================================================================
// BEHAVIORAL ENGAGEMENT COMPONENTS (30% total)
// ============================================================================

/**
 * Quest Score (15% weight)
 *
 * Binary: completed = 100, not completed = 0
 * Always 100% confidence (definitive data)
 */
function calculateQuestScore(completed: boolean): ScoreComponent {
  return {
    value: completed ? 100 : 0,
    weight: 0.15,
    confidence: 100,
    reason: completed ? "Quest completed" : "Quest not completed",
  };
}

/**
 * Social Score (7.5% weight)
 *
 * Based on circle check-ins:
 * - 0 check-ins → Score 0
 * - 1 check-in  → Score 70 (engaged)
 * - 2+ check-ins → Score 100 (highly engaged)
 */
function calculateSocialScore(checkins: number): ScoreComponent {
  const value = checkins === 0 ? 0 : checkins === 1 ? 70 : 100;

  return {
    value,
    weight: 0.075,
    confidence: 100,
    reason: `${checkins} circle check-in${checkins !== 1 ? "s" : ""}`,
  };
}

/**
 * Exercises Score (7.5% weight)
 *
 * Based on completed wellness exercises (breathing, meditation, etc.)
 * NOT the same as physical exercise minutes.
 *
 * Scoring:
 * - 0 exercises → 0 points
 * - 1 exercise → 60 points (engaged)
 * - 2 exercises → 80 points (active)
 * - 3+ exercises → 100 points (highly active)
 */
function calculateExercisesScore(exerciseMinutes: number): ScoreComponent {
  // Convert minutes to rough exercise count (assume ~10 min per exercise)
  const exerciseCount = Math.floor(exerciseMinutes / 10);

  let value: number;
  if (exerciseCount === 0) {
    value = 0;
  } else if (exerciseCount === 1) {
    value = 60;
  } else if (exerciseCount === 2) {
    value = 80;
  } else {
    value = 100;
  }

  return {
    value,
    weight: 0.075,
    confidence: 100,
    reason: `${exerciseMinutes} min of wellness exercises`,
  };
}

// ============================================================================
// PHYSICAL HEALTH COMPONENTS (30% total)
// ============================================================================

/**
 * Sleep Score (12% weight)
 *
 * Based on CDC guidelines (7-9 hours optimal) + quality if available.
 *
 * Duration scoring:
 * - 7-9 hours → 100 points (optimal)
 * - 6-7 hours → 80 points (adequate)
 * - 5-6 hours → 60 points (insufficient)
 * - <5 hours  → 40 points (critical)
 * - >9 hours  → 70 points (excessive)
 *
 * Quality modifier (if available):
 * - Adds up to ±20 points based on HealthKit sleep quality (0-100)
 */
function calculateSleepScore(hours?: number, quality?: number): ScoreComponent {
  if (hours === undefined && quality === undefined) {
    return {
      value: 60, // Neutral default
      weight: 0.12,
      confidence: 0,
      reason: "No sleep data",
    };
  }

  let durationScore = 60; // Default if only quality available

  if (hours !== undefined) {
    if (hours >= 7 && hours <= 9) {
      durationScore = 100;
    } else if (hours >= 6 && hours < 7) {
      durationScore = 80;
    } else if (hours >= 5 && hours < 6) {
      durationScore = 60;
    } else if (hours < 5) {
      durationScore = 40;
    } else {
      durationScore = 70;
    }
  }

  // Apply quality modifier if available
  let finalScore = durationScore;
  if (quality !== undefined) {
    // Quality is 0-100, map to -20 to +20 modifier
    const qualityModifier = (quality - 50) * 0.4; // 0→-20, 50→0, 100→+20
    finalScore = Math.round(durationScore + qualityModifier);
    finalScore = Math.max(0, Math.min(100, finalScore)); // Clamp to 0-100
  }

  const confidence = hours !== undefined ? 100 : 50;

  return {
    value: finalScore,
    weight: 0.12,
    confidence,
    reason: hours
      ? `${hours.toFixed(1)}h sleep${quality ? `, quality ${quality}%` : ""}`
      : `Sleep quality ${quality}%`,
  };
}

/**
 * Activity Score (10% weight)
 *
 * Prefers HealthKit steps if available, falls back to exercise minutes.
 *
 * HealthKit Steps:
 * - 10,000 steps = 100 points (CDC recommendation)
 * - Linear scaling: 5,000 steps = 50 points
 *
 * Exercise Minutes (fallback):
 * - 30 minutes = 100 points (WHO recommendation)
 * - Linear scaling: 15 minutes = 50 points
 */
function calculateActivityScore(
  steps?: number,
  biometricExerciseMinutes?: number,
): ScoreComponent {
  // Prefer HealthKit steps
  if (steps !== undefined) {
    const stepsScore = Math.min(100, Math.round((steps / 10000) * 100));
    return {
      value: stepsScore,
      weight: 0.1,
      confidence: 100,
      reason: `${steps.toLocaleString()} steps`,
    };
  }

  // Use biometric exercise minutes if available (NOT app-tracked exercises - those are behavioral)
  if (biometricExerciseMinutes !== undefined && biometricExerciseMinutes > 0) {
    const exerciseScore = Math.min(
      100,
      Math.round((biometricExerciseMinutes / 30) * 100),
    );
    return {
      value: exerciseScore,
      weight: 0.1,
      confidence: 100,
      reason: `${biometricExerciseMinutes} min exercise (HealthKit)`,
    };
  }

  // No physical activity data available
  return {
    value: 50, // Neutral default - assume moderate activity
    weight: 0.1,
    confidence: 0,
    reason: "No activity data",
  };
}

/**
 * Stress Resilience Score (8% weight)
 *
 * Combines HRV (heart rate variability) and resting heart rate.
 * Both are advanced biometrics from HealthKit.
 *
 * HRV scoring (higher = better stress resilience):
 * - >100ms → 100 points (Excellent)
 * - 80-100ms → 80 points (Very good)
 * - 60-80ms → 60 points (Good)
 * - 40-60ms → 40 points (Fair)
 * - <40ms → 20 points (Poor)
 *
 * Resting HR scoring (lower = better cardiovascular health):
 * - <60 BPM → 100 points (Athlete level)
 * - 60-70 BPM → 80 points (Excellent)
 * - 70-80 BPM → 60 points (Good)
 * - 80-90 BPM → 40 points (Average)
 * - >90 BPM → 20 points (High)
 *
 * Combined: Average both if available, otherwise use whichever is available
 */
function calculateStressResilienceScore(
  hrvMs?: number,
  restingHR?: number,
): ScoreComponent {
  if (hrvMs === undefined && restingHR === undefined) {
    return {
      value: 70, // Assume moderate resilience
      weight: 0.08,
      confidence: 0,
      reason: "No stress resilience data (HRV/RHR)",
    };
  }

  let hrvScore = 70; // Default
  let rhrScore = 70; // Default
  const parts: string[] = [];

  if (hrvMs !== undefined) {
    if (hrvMs >= 100) {
      hrvScore = 100;
    } else if (hrvMs >= 80) {
      hrvScore = 80 + Math.round(((hrvMs - 80) / 20) * 20);
    } else if (hrvMs >= 60) {
      hrvScore = 60 + Math.round(((hrvMs - 60) / 20) * 20);
    } else if (hrvMs >= 40) {
      hrvScore = 40 + Math.round(((hrvMs - 40) / 20) * 20);
    } else {
      hrvScore = Math.round((hrvMs / 40) * 20);
    }
    parts.push(`HRV ${Math.round(hrvMs)}ms`);
  }

  if (restingHR !== undefined) {
    if (restingHR < 60) {
      rhrScore = 100;
    } else if (restingHR < 70) {
      rhrScore = 80 + Math.round(((70 - restingHR) / 10) * 20);
    } else if (restingHR < 80) {
      rhrScore = 60 + Math.round(((80 - restingHR) / 10) * 20);
    } else if (restingHR < 90) {
      rhrScore = 40 + Math.round(((90 - restingHR) / 10) * 20);
    } else {
      rhrScore = Math.max(0, 40 - Math.round(((restingHR - 90) / 10) * 20));
    }
    parts.push(`RHR ${Math.round(restingHR)} BPM`);
  }

  // Average available scores
  const finalScore =
    hrvMs !== undefined && restingHR !== undefined
      ? Math.round((hrvScore + rhrScore) / 2)
      : hrvMs !== undefined
        ? hrvScore
        : rhrScore;

  const confidence =
    (hrvMs !== undefined ? 50 : 0) + (restingHR !== undefined ? 50 : 0);

  return {
    value: finalScore,
    weight: 0.08,
    confidence,
    reason: parts.join(", "),
  };
}
