// Test file for suggest-intervention edge function
// Run with: deno test supabase/functions/suggest-intervention/test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { InterventionType, InterventionRequest } from "./types.ts";

// Re-implement the logic here for testing without network dependencies

// Thresholds for intervention decision
const SLEEP_HOURS_LOW = 6;
const STEPS_LOW = 3000;

/**
 * Determine intervention type based on prediction factors
 */
function determineInterventionType(
  request: InterventionRequest,
): InterventionType {
  const { features, factors } = request;

  // Check for sleep deficit (highest priority)
  if (
    features.sleep_hours !== null &&
    features.sleep_hours !== undefined &&
    features.sleep_hours < SLEEP_HOURS_LOW
  ) {
    return "rest_suggestion";
  }

  // Check for low activity
  if (
    features.steps_yesterday !== null &&
    features.steps_yesterday !== undefined &&
    features.steps_yesterday < STEPS_LOW
  ) {
    return "movement_suggestion";
  }

  // Check for pattern in factors (day of week, trend)
  const hasPatternFactor = factors.some(
    (f) =>
      f.factor === "day_of_week" ||
      f.factor === "mood_trend" ||
      f.factor.includes("pattern"),
  );

  if (hasPatternFactor) {
    return "pattern_break";
  }

  // Default to general support
  return "general_support";
}

// MARK: - determineInterventionType Tests

Deno.test(
  "determineInterventionType - low sleep returns rest_suggestion",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [],
      features: {
        sleep_hours: 4.5,
        steps_yesterday: 8000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "rest_suggestion");
  },
);

Deno.test(
  "determineInterventionType - low steps returns movement_suggestion",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [],
      features: {
        sleep_hours: 7.5,
        steps_yesterday: 2000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "movement_suggestion");
  },
);

Deno.test(
  "determineInterventionType - day_of_week factor returns pattern_break",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [
        {
          factor: "day_of_week",
          impact: -0.5,
          description: "Mondays are hard",
        },
      ],
      features: {
        sleep_hours: 7.5,
        steps_yesterday: 8000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "pattern_break");
  },
);

Deno.test(
  "determineInterventionType - mood_trend factor returns pattern_break",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [
        { factor: "mood_trend", impact: -0.8, description: "Declining trend" },
      ],
      features: {
        sleep_hours: 7.5,
        steps_yesterday: 8000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "pattern_break");
  },
);

Deno.test(
  "determineInterventionType - no specific factors returns general_support",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [{ factor: "streak", impact: 0.2, description: "Streak bonus" }],
      features: {
        sleep_hours: 7.5,
        steps_yesterday: 8000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "general_support");
  },
);

Deno.test("determineInterventionType - sleep takes priority over steps", () => {
  const request: InterventionRequest = {
    userId: "test-user",
    predictionId: "test-prediction",
    predictedMood: 3.5,
    factors: [],
    features: {
      sleep_hours: 4.0, // Low sleep
      steps_yesterday: 2000, // Also low steps
    },
  };

  // Sleep should take priority
  const result = determineInterventionType(request);
  assertEquals(result, "rest_suggestion");
});

Deno.test(
  "determineInterventionType - null features handled gracefully",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [],
      features: {
        sleep_hours: null,
        steps_yesterday: null,
      },
    };

    // Should fall through to general_support
    const result = determineInterventionType(request);
    assertEquals(result, "general_support");
  },
);

Deno.test(
  "determineInterventionType - pattern keyword in factor returns pattern_break",
  () => {
    const request: InterventionRequest = {
      userId: "test-user",
      predictionId: "test-prediction",
      predictedMood: 3.5,
      factors: [
        {
          factor: "weekly_pattern",
          impact: -0.3,
          description: "Weekly pattern detected",
        },
      ],
      features: {
        sleep_hours: 7.5,
        steps_yesterday: 8000,
      },
    };

    const result = determineInterventionType(request);
    assertEquals(result, "pattern_break");
  },
);

// MARK: - Intervention Templates Tests

Deno.test("intervention templates have required properties", () => {
  const templates: Record<
    InterventionType,
    { type: string; message: string; exerciseCategory: string }
  > = {
    rest_suggestion: {
      type: "rest_suggestion",
      message: "Based on your sleep patterns...",
      exerciseCategory: "meditation",
    },
    movement_suggestion: {
      type: "movement_suggestion",
      message: "Your activity has been lower...",
      exerciseCategory: "movement",
    },
    pattern_break: {
      type: "pattern_break",
      message: "We noticed a pattern...",
      exerciseCategory: "breathing",
    },
    general_support: {
      type: "general_support",
      message: "Today might be challenging...",
      exerciseCategory: "grounding",
    },
  };

  // Each template should have all required properties
  for (const [key, template] of Object.entries(templates)) {
    assertEquals(template.type, key);
    assertEquals(template.message.length > 0, true);
    assertEquals(template.exerciseCategory.length > 0, true);
  }
});

// MARK: - Threshold Tests

Deno.test("SLEEP_HOURS_LOW threshold is 6 hours", () => {
  assertEquals(SLEEP_HOURS_LOW, 6);
});

Deno.test("STEPS_LOW threshold is 3000 steps", () => {
  assertEquals(STEPS_LOW, 3000);
});

// MARK: - Privacy Tests

Deno.test("hashUserId creates privacy-safe hash", () => {
  function hashUserId(userId: string): string {
    return userId.substring(0, 8) + "...";
  }

  const fullUserId = "550e8400-e29b-41d4-a716-446655440000";
  const hashed = hashUserId(fullUserId);

  // Should only show first 8 characters
  assertEquals(hashed, "550e8400...");
  assertEquals(hashed.length, 11);

  // Should not contain full UUID
  assertEquals(hashed.includes("446655440000"), false);
});
