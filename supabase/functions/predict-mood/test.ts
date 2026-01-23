// Test file for predict-mood edge function
// Run with: deno test supabase/functions/predict-mood/test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  calculatePrediction,
  shouldTriggerIntervention,
  DEFAULT_WEIGHTS,
} from "./algorithms.ts";
import type { PredictionFeatures } from "./types.ts";

// Helper to create feature set with defaults
function createFeatures(
  overrides: Partial<PredictionFeatures> = {},
): PredictionFeatures {
  return {
    mood_avg_7d: 2.5, // 1-5 scale
    mood_avg_14d: 2.5,
    mood_trend_7d: 0,
    previous_mood: 2.5,
    sleep_hours: 7.5,
    steps_yesterday: 8000,
    exercise_minutes_7d: 100,
    day_of_week: 3, // Wednesday
    hour_of_day: 8,
    streak_days: 7,
    has_sleep_data: true,
    has_steps_data: true,
    timezone: "America/New_York",
    ...overrides,
  };
}

// MARK: - calculatePrediction Tests

Deno.test("calculatePrediction - baseline with average features", () => {
  const features = createFeatures();
  const result = calculatePrediction(features, DEFAULT_WEIGHTS);

  // Should return a value around baseline (5.0 on 1-10 scale)
  assertEquals(
    result.predictedMood >= 4.0 && result.predictedMood <= 7.0,
    true,
  );
  assertEquals(result.confidence >= 0.5 && result.confidence <= 1.0, true);
  assertEquals(result.modelVersion, "v1.0-regression");
});

Deno.test(
  "calculatePrediction - high mood features produce high prediction",
  () => {
    const features = createFeatures({
      mood_avg_7d: 4.5, // High mood (1-5 scale)
      mood_trend_7d: 0.5, // Improving trend
      sleep_hours: 8.5, // Good sleep
      steps_yesterday: 12000, // Active
      streak_days: 30, // Long streak
      exercise_minutes_7d: 200, // Active week
    });

    const result = calculatePrediction(features, DEFAULT_WEIGHTS);
    assertEquals(result.predictedMood >= 7.0, true);
    assertEquals(result.factors.length > 0, true);
  },
);

Deno.test(
  "calculatePrediction - low mood features produce low prediction",
  () => {
    const features = createFeatures({
      mood_avg_7d: 1.5, // Low mood (1-5 scale)
      mood_trend_7d: -0.5, // Declining trend
      sleep_hours: 4.0, // Poor sleep
      steps_yesterday: 1000, // Inactive
      streak_days: 0, // No streak
      exercise_minutes_7d: 0, // No exercise
      day_of_week: 1, // Monday
    });

    const result = calculatePrediction(features, DEFAULT_WEIGHTS);
    assertEquals(result.predictedMood <= 4.0, true);
    assertEquals(result.factors.length > 0, true);
  },
);

Deno.test(
  "calculatePrediction - handles null biometric features gracefully",
  () => {
    const features = createFeatures({
      sleep_hours: null,
      steps_yesterday: null,
      has_sleep_data: false,
      has_steps_data: false,
    });

    const result = calculatePrediction(features, DEFAULT_WEIGHTS);

    // Should still return valid prediction
    assertEquals(
      result.predictedMood >= 1.0 && result.predictedMood <= 10.0,
      true,
    );
    assertEquals(result.confidence >= 0.0 && result.confidence <= 1.0, true);
  },
);

Deno.test("calculatePrediction - prediction clamped to 1-10 range", () => {
  // Extreme low features
  const lowFeatures = createFeatures({
    mood_avg_7d: 1.0,
    mood_trend_7d: -2.0,
    sleep_hours: 2.0,
    steps_yesterday: 0,
    streak_days: 0,
    day_of_week: 1,
  });

  const lowResult = calculatePrediction(lowFeatures, DEFAULT_WEIGHTS);
  assertEquals(lowResult.predictedMood >= 1.0, true);

  // Extreme high features
  const highFeatures = createFeatures({
    mood_avg_7d: 5.0,
    mood_trend_7d: 2.0,
    sleep_hours: 10.0,
    steps_yesterday: 20000,
    streak_days: 365,
    exercise_minutes_7d: 500,
    day_of_week: 5,
  });

  const highResult = calculatePrediction(highFeatures, DEFAULT_WEIGHTS);
  assertEquals(highResult.predictedMood <= 10.0, true);
});

Deno.test("calculatePrediction - factors include sleep when low", () => {
  const features = createFeatures({
    sleep_hours: 4.0, // Low sleep
    has_sleep_data: true,
  });

  const result = calculatePrediction(features, DEFAULT_WEIGHTS);

  const sleepFactor = result.factors.find((f) => f.factor === "sleep_hours");
  assertEquals(sleepFactor !== undefined, true);
  assertEquals(sleepFactor!.impact < 0, true);
});

Deno.test("calculatePrediction - Friday has positive day factor", () => {
  const features = createFeatures({
    day_of_week: 5, // Friday
  });

  const result = calculatePrediction(features, DEFAULT_WEIGHTS);

  const dayFactor = result.factors.find((f) => f.factor === "day_of_week");
  // Friday should have positive impact
  if (dayFactor) {
    assertEquals(dayFactor.impact > 0, true);
    assertEquals(dayFactor.description.includes("Friday"), true);
  }
});

Deno.test("calculatePrediction - Monday has negative day factor", () => {
  const features = createFeatures({
    day_of_week: 1, // Monday
  });

  const result = calculatePrediction(features, DEFAULT_WEIGHTS);

  const dayFactor = result.factors.find((f) => f.factor === "day_of_week");
  // Monday should have negative impact
  if (dayFactor) {
    assertEquals(dayFactor.impact < 0, true);
    assertEquals(dayFactor.description.includes("Monday"), true);
  }
});

// MARK: - shouldTriggerIntervention Tests

Deno.test(
  "shouldTriggerIntervention - triggers for low mood high confidence",
  () => {
    const result = shouldTriggerIntervention(3.5, 0.75);
    assertEquals(result, true);
  },
);

Deno.test("shouldTriggerIntervention - does not trigger for high mood", () => {
  const result = shouldTriggerIntervention(7.0, 0.85);
  assertEquals(result, false);
});

Deno.test(
  "shouldTriggerIntervention - does not trigger for low confidence",
  () => {
    const result = shouldTriggerIntervention(3.5, 0.45);
    assertEquals(result, false);
  },
);

Deno.test("shouldTriggerIntervention - boundary at mood threshold", () => {
  // At threshold (4.0), should NOT trigger
  const atThreshold = shouldTriggerIntervention(4.0, 0.75);
  assertEquals(atThreshold, false);

  // Just below threshold, should trigger
  const belowThreshold = shouldTriggerIntervention(3.9, 0.75);
  assertEquals(belowThreshold, true);
});

Deno.test(
  "shouldTriggerIntervention - boundary at confidence threshold",
  () => {
    // At threshold (0.6), should NOT trigger
    const atThreshold = shouldTriggerIntervention(3.0, 0.6);
    assertEquals(atThreshold, false);

    // Just above threshold, should trigger
    const aboveThreshold = shouldTriggerIntervention(3.0, 0.61);
    assertEquals(aboveThreshold, true);
  },
);

// MARK: - DEFAULT_WEIGHTS Tests

Deno.test("DEFAULT_WEIGHTS - contains expected keys", () => {
  assertEquals("mood_avg_7d" in DEFAULT_WEIGHTS, true);
  assertEquals("mood_trend_7d" in DEFAULT_WEIGHTS, true);
  assertEquals("sleep_hours" in DEFAULT_WEIGHTS, true);
  assertEquals("steps_yesterday" in DEFAULT_WEIGHTS, true);
  assertEquals("day_of_week" in DEFAULT_WEIGHTS, true);
  assertEquals("exercise_minutes" in DEFAULT_WEIGHTS, true);
});

Deno.test("DEFAULT_WEIGHTS - mood_avg_7d has highest weight", () => {
  // Average mood should be the most important predictor
  assertEquals(
    DEFAULT_WEIGHTS.mood_avg_7d >= DEFAULT_WEIGHTS.sleep_hours,
    true,
  );
  assertEquals(
    DEFAULT_WEIGHTS.mood_avg_7d >= DEFAULT_WEIGHTS.steps_yesterday,
    true,
  );
  assertEquals(
    DEFAULT_WEIGHTS.mood_avg_7d >= DEFAULT_WEIGHTS.exercise_minutes,
    true,
  );
});

Deno.test("DEFAULT_WEIGHTS - all weights sum to 1.0", () => {
  const total =
    DEFAULT_WEIGHTS.mood_avg_7d +
    DEFAULT_WEIGHTS.mood_trend_7d +
    DEFAULT_WEIGHTS.sleep_hours +
    DEFAULT_WEIGHTS.steps_yesterday +
    DEFAULT_WEIGHTS.day_of_week +
    DEFAULT_WEIGHTS.exercise_minutes;

  assertEquals(total === 1.0, true);
});
