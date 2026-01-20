/**
 * Unit tests for signature-builder.ts
 * Run with: deno test signature-builder.test.ts
 */

import {
  assertEquals,
  assertRejects,
  assert,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildSignaturePatterns, UserPattern } from "./signature-builder.ts";

// Test data helpers
function createMockPattern(overrides: Partial<UserPattern> = {}): UserPattern {
  return {
    id: "test-pattern-id",
    userId: "test-user-123",
    patternType: "stress_high_mood",
    patternKey: "work_stress",
    confidenceScore: 0.8,
    evidenceCount: 14,
    firstDetectedAt: "2026-01-01T00:00:00Z",
    lastDetectedAt: "2026-01-15T00:00:00Z",
    patternData: {},
    isActive: true,
    ...overrides,
  };
}

// ============================================================================
// Input Validation Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - validates userId is non-empty string",
  async () => {
    await assertRejects(
      () => buildSignaturePatterns("", []),
      Error,
      "Invalid userId: must be non-empty string",
    );

    await assertRejects(
      () => buildSignaturePatterns("   ", []),
      Error,
      "Invalid userId: must be non-empty string",
    );
  },
);

Deno.test(
  "buildSignaturePatterns - validates allPatterns is an array",
  async () => {
    await assertRejects(
      // @ts-ignore - intentionally passing invalid type
      () => buildSignaturePatterns("user-123", null),
      Error,
      "Invalid allPatterns: must be an array",
    );

    await assertRejects(
      // @ts-ignore - intentionally passing invalid type
      () => buildSignaturePatterns("user-123", "not-an-array"),
      Error,
      "Invalid allPatterns: must be an array",
    );
  },
);

Deno.test("buildSignaturePatterns - accepts valid inputs", async () => {
  const result = await buildSignaturePatterns("user-123", []);
  assertEquals(result, []);
});

// ============================================================================
// Confidence Filtering Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - filters low-confidence patterns",
  async () => {
    const lowConfidence = createMockPattern({
      confidenceScore: 0.3, // Below 0.5 threshold
    });

    const result = await buildSignaturePatterns("user-123", [lowConfidence]);
    assertEquals(
      result.length,
      0,
      "Low-confidence patterns should be filtered",
    );
  },
);

Deno.test(
  "buildSignaturePatterns - includes high-confidence patterns",
  async () => {
    const highConfidence = createMockPattern({
      confidenceScore: 0.8,
      patternType: "stress_high_mood",
    });

    const result = await buildSignaturePatterns("user-123", [highConfidence]);
    assertEquals(
      result.length,
      1,
      "High-confidence patterns should be included",
    );
  },
);

Deno.test("buildSignaturePatterns - filters inactive patterns", async () => {
  const inactive = createMockPattern({
    isActive: false,
    confidenceScore: 0.9,
  });

  const result = await buildSignaturePatterns("user-123", [inactive]);
  assertEquals(result.length, 0, "Inactive patterns should be filtered");
});

// ============================================================================
// Stress Trigger Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - creates stress trigger signature",
  async () => {
    const trigger = createMockPattern({
      patternType: "stress_high_mood",
      patternKey: "work_stress",
      confidenceScore: 0.85,
      evidenceCount: 20,
    });

    const result = await buildSignaturePatterns("user-123", [trigger]);

    assertEquals(result.length, 1);
    assertEquals(result[0].patternType, "signature_stress_trigger");
    assertEquals(result[0].patternKey, "work_stress");
    assertEquals(result[0].confidenceScore, 0.85);
    assertEquals(result[0].evidenceCount, 20);
    assert(result[0].patternData.category);
    assert(result[0].patternData.frequency);
    assert(Array.isArray(result[0].patternData.timeline));
  },
);

Deno.test(
  "buildSignaturePatterns - categorizes stress triggers correctly",
  async () => {
    const workStress = createMockPattern({
      patternType: "anxiety_spike",
      patternKey: "work_stress",
    });

    const result = await buildSignaturePatterns("user-123", [workStress]);
    assertEquals(result[0].patternData.category, "Work Stress");
  },
);

// ============================================================================
// Coping Strategy Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - creates coping strategy signature",
  async () => {
    const strategy = createMockPattern({
      patternType: "exercise_correlation",
      patternKey: "breathing_exercises",
      confidenceScore: 0.75,
      evidenceCount: 15,
      patternData: {
        exercises: ["Deep Breathing", "4-7-8 Breathing"],
      },
    });

    const result = await buildSignaturePatterns("user-123", [strategy]);

    assertEquals(result.length, 1);
    assertEquals(result[0].patternType, "signature_coping_strategy");
    assertEquals(result[0].patternKey, "breathing_exercises");
    assertEquals(result[0].patternData.category, "Breathing Techniques");
    assertEquals(result[0].patternData.topExercises, [
      "Deep Breathing",
      "4-7-8 Breathing",
    ]);
  },
);

Deno.test(
  "buildSignaturePatterns - extracts top exercises safely",
  async () => {
    const strategyWithInvalidData = createMockPattern({
      patternType: "mood_improvement",
      patternKey: "meditation",
      patternData: {
        exercises: [123, "Valid Exercise", null, "Another Valid"], // Mixed types
      },
    });

    const result = await buildSignaturePatterns("user-123", [
      strategyWithInvalidData,
    ]);

    // Should filter out non-string values
    assertEquals(result[0].patternData.topExercises, [
      "Valid Exercise",
      "Another Valid",
    ]);
  },
);

// ============================================================================
// Time Pattern Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - creates time pattern signature",
  async () => {
    const timePattern = createMockPattern({
      patternType: "day_of_week",
      patternKey: "monday",
      confidenceScore: 0.7,
      evidenceCount: 12,
      patternData: {
        peakHours: [9, 14, 17],
      },
    });

    const result = await buildSignaturePatterns("user-123", [timePattern]);

    assertEquals(result.length, 1);
    assertEquals(result[0].patternType, "signature_time_pattern");
    assertEquals(result[0].patternKey, "monday");
    assertEquals(result[0].patternData.category, "Monday Patterns");
    assertEquals(result[0].patternData.peakTimes, ["09:00", "14:00", "17:00"]);
  },
);

Deno.test(
  "buildSignaturePatterns - handles invalid peak hours safely",
  async () => {
    const timePattern = createMockPattern({
      patternType: "time_of_day",
      patternKey: "morning_routine",
      patternData: {
        peakHours: [7, "not-a-number", NaN, 12], // Mixed types
      },
    });

    const result = await buildSignaturePatterns("user-123", [timePattern]);

    // Should filter out non-numeric values
    assertEquals(result[0].patternData.peakTimes, ["07:00", "12:00"]);
  },
);

// ============================================================================
// Frequency Calculation Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - calculates frequency correctly",
  async () => {
    const pattern = createMockPattern({
      patternType: "stress_high_mood",
      patternKey: "work_stress",
      evidenceCount: 14, // 14 occurrences over 2 weeks = 7/week
      firstDetectedAt: "2026-01-01T00:00:00Z",
      lastDetectedAt: "2026-01-15T00:00:00Z", // Exactly 14 days
    });

    const result = await buildSignaturePatterns("user-123", [pattern]);

    assertEquals(result[0].patternData.frequency, 7); // 14 / 2 weeks = 7 per week
  },
);

Deno.test(
  "buildSignaturePatterns - handles division by zero with MIN_WEEKS_ACTIVE",
  async () => {
    const pattern = createMockPattern({
      patternType: "anxiety_spike",
      patternKey: "social_anxiety",
      evidenceCount: 5,
      firstDetectedAt: "2026-01-20T00:00:00Z",
      lastDetectedAt: "2026-01-20T12:00:00Z", // Same day
    });

    const result = await buildSignaturePatterns("user-123", [pattern]);

    // daysSinceFirst = max(1, 0.5) = 1 day
    // weeksActive = max(0.1, 1/7) = 1/7 = 0.142857 weeks
    // frequency = 5 / 0.142857 = 35 per week
    assertEquals(result[0].patternData.frequency, 35);
  },
);

Deno.test(
  "buildSignaturePatterns - returns 0 frequency for invalid dates",
  async () => {
    const pattern = createMockPattern({
      patternType: "stress_high_mood",
      patternKey: "uncertainty",
      evidenceCount: 10,
      firstDetectedAt: "invalid-date",
      lastDetectedAt: "2026-01-15T00:00:00Z",
    });

    const result = await buildSignaturePatterns("user-123", [pattern]);

    assertEquals(result[0].patternData.frequency, 0); // Invalid date returns 0
  },
);

// ============================================================================
// Timeline Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - creates timeline with start and end points",
  async () => {
    const pattern = createMockPattern({
      patternType: "stress_high_mood",
      patternKey: "health_concern",
      evidenceCount: 25,
      firstDetectedAt: "2026-01-01T00:00:00Z",
      lastDetectedAt: "2026-01-30T00:00:00Z",
    });

    const result = await buildSignaturePatterns("user-123", [pattern]);

    const timeline = result[0].patternData.timeline;
    assertEquals(timeline.length, 2);
    assertEquals(timeline[0].date, "2026-01-01T00:00:00Z");
    assertEquals(timeline[0].count, 1);
    assertEquals(timeline[1].date, "2026-01-30T00:00:00Z");
    assertEquals(timeline[1].count, 25);
  },
);

// ============================================================================
// Multiple Pattern Types Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - processes multiple pattern types",
  async () => {
    const patterns = [
      createMockPattern({
        patternType: "stress_high_mood",
        patternKey: "work_stress",
      }),
      createMockPattern({
        patternType: "exercise_correlation",
        patternKey: "physical_activity",
      }),
      createMockPattern({
        patternType: "day_of_week",
        patternKey: "friday",
      }),
    ];

    const result = await buildSignaturePatterns("user-123", patterns);

    assertEquals(result.length, 3);
    assertEquals(result[0].patternType, "signature_stress_trigger");
    assertEquals(result[1].patternType, "signature_coping_strategy");
    assertEquals(result[2].patternType, "signature_time_pattern");
  },
);

Deno.test(
  "buildSignaturePatterns - filters mixed confidence patterns",
  async () => {
    const patterns = [
      createMockPattern({
        patternType: "stress_high_mood",
        patternKey: "work_stress",
        confidenceScore: 0.9, // High - should be included
      }),
      createMockPattern({
        patternType: "anxiety_spike",
        patternKey: "social_anxiety",
        confidenceScore: 0.3, // Low - should be filtered
      }),
      createMockPattern({
        patternType: "exercise_correlation",
        patternKey: "meditation",
        confidenceScore: 0.6, // Medium - should be included
      }),
    ];

    const result = await buildSignaturePatterns("user-123", patterns);

    assertEquals(result.length, 2); // Only 2 patterns above 0.5 threshold
  },
);

// ============================================================================
// Edge Case Tests
// ============================================================================

Deno.test("buildSignaturePatterns - handles empty pattern array", async () => {
  const result = await buildSignaturePatterns("user-123", []);
  assertEquals(result, []);
});

Deno.test(
  "buildSignaturePatterns - handles patterns with no matching type",
  async () => {
    const unknownPattern = createMockPattern({
      patternType: "unknown_pattern_type",
      patternKey: "some_key",
    });

    const result = await buildSignaturePatterns("user-123", [unknownPattern]);

    // Unknown pattern types are not processed into signatures
    assertEquals(result.length, 0);
  },
);

Deno.test(
  "buildSignaturePatterns - handles missing pattern_data gracefully",
  async () => {
    const noData = createMockPattern({
      patternType: "exercise_correlation",
      patternKey: "journaling",
      // @ts-ignore - testing runtime behavior
      patternData: null,
    });

    const result = await buildSignaturePatterns("user-123", [noData]);

    assertEquals(result.length, 1);
    assertEquals(result[0].patternData.topExercises, []); // Empty array when no data
  },
);

// ============================================================================
// Categorization Tests
// ============================================================================

Deno.test(
  "buildSignaturePatterns - uses default category for unknown patterns",
  async () => {
    const unknownTrigger = createMockPattern({
      patternType: "stress_high_mood",
      patternKey: "completely_unknown_trigger",
    });

    const result = await buildSignaturePatterns("user-123", [unknownTrigger]);

    assertEquals(result[0].patternData.category, "Other Stressors");
  },
);

Deno.test("buildSignaturePatterns - matches partial pattern keys", async () => {
  const partialMatch = createMockPattern({
    patternType: "exercise_correlation",
    patternKey: "breathing_exercises_daily", // Contains "breathing_exercises"
  });

  const result = await buildSignaturePatterns("user-123", [partialMatch]);

  assertEquals(result[0].patternData.category, "Breathing Techniques");
});

Deno.test(
  "buildSignaturePatterns - time patterns are case-insensitive",
  async () => {
    const upperCase = createMockPattern({
      patternType: "day_of_week",
      patternKey: "MONDAY", // Uppercase
    });

    const result = await buildSignaturePatterns("user-123", [upperCase]);

    assertEquals(result[0].patternData.category, "Monday Patterns");
  },
);
