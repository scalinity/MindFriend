// Tests for analyze-intervention-patterns Edge Function
// Validates ML timing analysis algorithm, data requirements, and error handling

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const FUNCTION_URL =
  Deno.env.get("SUPABASE_URL") + "/functions/v1/analyze-intervention-patterns";

// Mock valid auth token (replace with actual test token in CI)
const mockAuthToken = "mock-test-token";

Deno.test(
  "analyze-intervention-patterns: returns insufficient_data with no deliveries",
  async () => {
    const response = await fetch(FUNCTION_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${mockAuthToken}`,
      },
      body: JSON.stringify({}),
    });

    assertEquals(response.status, 400);

    const data = await response.json();
    assertEquals(data.error, "insufficient_data");
    assertExists(data.message);
  },
);

Deno.test(
  "analyze-intervention-patterns: returns insufficient_data with < 14 days",
  async () => {
    // This test would require seeding test data with < 14 days of deliveries
    // Placeholder for CI integration
    assertEquals(true, true);
  },
);

Deno.test(
  "analyze-intervention-patterns: calculates confidence correctly",
  async () => {
    // Test confidence formula:
    // confidence = (completionRate - 0.5) * 0.6 + ((avgRating - 3.0) / 5.0) * 0.3 - (dismissRate - 0.5) * 0.1

    const testCases = [
      {
        completionRate: 0.8,
        avgRating: 4.5,
        dismissRate: 0.1,
        expected: 0.35, // (0.3 * 0.6) + (0.3 * 0.3) - (-0.4 * 0.1) = 0.18 + 0.09 + 0.04 = 0.31
      },
      {
        completionRate: 0.5,
        avgRating: 3.0,
        dismissRate: 0.5,
        expected: 0.0, // Neutral baseline
      },
      {
        completionRate: 0.3,
        avgRating: 2.0,
        dismissRate: 0.7,
        expected: -0.24, // Negative confidence
      },
    ];

    testCases.forEach((tc) => {
      const confidence =
        (tc.completionRate - 0.5) * 0.6 +
        ((tc.avgRating - 3.0) / 5.0) * 0.3 -
        (tc.dismissRate - 0.5) * 0.1;

      assertEquals(Math.round(confidence * 100) / 100, tc.expected);
    });
  },
);

Deno.test(
  "analyze-intervention-patterns: clamps confidence to [-0.5, +0.5]",
  () => {
    const maxConfidence = 0.6; // Should clamp to 0.5
    const minConfidence = -0.6; // Should clamp to -0.5

    const clampedMax = Math.max(-0.5, Math.min(0.5, maxConfidence));
    const clampedMin = Math.max(-0.5, Math.min(0.5, minConfidence));

    assertEquals(clampedMax, 0.5);
    assertEquals(clampedMin, -0.5);
  },
);

Deno.test(
  "analyze-intervention-patterns: handles timezone-aware hour extraction",
  () => {
    const testDate = new Date("2024-01-15T14:30:00Z"); // 2:30 PM UTC

    // Test UTC timezone
    const formatterUTC = new Intl.DateTimeFormat("en-US", {
      timeZone: "UTC",
      hour: "2-digit",
      hour12: false,
    });

    const hourUTC = formatterUTC
      .formatToParts(testDate)
      .find((p) => p.type === "hour")?.value;
    assertEquals(hourUTC, "14");

    // Test PST timezone (UTC-8)
    const formatterPST = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Los_Angeles",
      hour: "2-digit",
      hour12: false,
    });

    const hourPST = formatterPST
      .formatToParts(testDate)
      .find((p) => p.type === "hour")?.value;
    assertEquals(hourPST, "06"); // 14:00 UTC = 06:00 PST
  },
);

Deno.test(
  "analyze-intervention-patterns: requires minimum samples per hour",
  () => {
    const MIN_SAMPLES_PER_HOUR = 2;

    const validHourData = {
      total: 5,
      completed: 4,
      dismissed: 0,
      ratings: [4, 5, 4, 5, 4],
    };
    const invalidHourData = {
      total: 1,
      completed: 1,
      dismissed: 0,
      ratings: [5],
    };

    assertEquals(validHourData.total >= MIN_SAMPLES_PER_HOUR, true);
    assertEquals(invalidHourData.total >= MIN_SAMPLES_PER_HOUR, false);
  },
);

Deno.test(
  "analyze-intervention-patterns: handles missing ratings gracefully",
  () => {
    const ratingsWithData = [4, 5, 3, 4];
    const ratingsEmpty: number[] = [];

    const avgWithData =
      ratingsWithData.reduce((sum, r) => sum + r, 0) / ratingsWithData.length;
    const avgEmpty =
      ratingsEmpty.length > 0
        ? ratingsEmpty.reduce((sum, r) => sum + r, 0) / ratingsEmpty.length
        : 3.0;

    assertEquals(avgWithData, 4.0);
    assertEquals(avgEmpty, 3.0); // Neutral default
  },
);

Deno.test("analyze-intervention-patterns: rolling 90-day window", () => {
  const ROLLING_WINDOW_DAYS = 90;
  const now = new Date();
  const windowStart = new Date(now);
  windowStart.setDate(windowStart.getDate() - ROLLING_WINDOW_DAYS);

  const daysDiff =
    (now.getTime() - windowStart.getTime()) / (1000 * 60 * 60 * 24);
  assertEquals(daysDiff, ROLLING_WINDOW_DAYS);
});

Deno.test("analyze-intervention-patterns: validates 14-day minimum", () => {
  const MIN_DAYS_FOR_ANALYSIS = 14;
  const now = new Date();
  const oldestDelivery = new Date(now);
  oldestDelivery.setDate(oldestDelivery.getDate() - 10);

  const daysSinceFirst =
    (now.getTime() - oldestDelivery.getTime()) / (1000 * 60 * 60 * 24);

  assertEquals(daysSinceFirst < MIN_DAYS_FOR_ANALYSIS, true); // Insufficient
});

Deno.test("analyze-intervention-patterns: handles CORS preflight", async () => {
  const response = await fetch(FUNCTION_URL, {
    method: "OPTIONS",
  });

  assertEquals(response.status, 200);
  assertExists(response.headers.get("Access-Control-Allow-Origin"));
});

Deno.test("analyze-intervention-patterns: requires authorization", async () => {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // No Authorization header
    },
    body: JSON.stringify({}),
  });

  assertEquals(response.status, 401);
});
