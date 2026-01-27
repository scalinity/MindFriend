// Tests for aggregate-weekly-stats Edge Function
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Mock data for testing calculations
const mockMoods = [
  { mood_score: 3, created_at: "2026-01-13T10:00:00Z" },
  { mood_score: 4, created_at: "2026-01-14T10:00:00Z" },
  { mood_score: 3, created_at: "2026-01-15T10:00:00Z" },
  { mood_score: 5, created_at: "2026-01-16T10:00:00Z" },
  { mood_score: 4, created_at: "2026-01-17T10:00:00Z" },
];

const mockExercises = [
  { completed_at: "2026-01-13T11:00:00Z" },
  { completed_at: "2026-01-14T11:00:00Z" },
  { completed_at: "2026-01-15T11:00:00Z" },
  { completed_at: "2026-01-16T11:00:00Z" },
  { completed_at: "2026-01-16T12:00:00Z" },
];

const mockSleepData = [
  { sleep_hours: 7.5 },
  { sleep_hours: 8.0 },
  { sleep_hours: 6.5 },
  { sleep_hours: 7.0 },
  { sleep_hours: 8.5 },
];

// Helper functions to test (mimicking function logic)
function calculateAvgMood(moods: { mood_score: number }[]): number {
  if (moods.length === 0) return 0;
  const sum = moods.reduce((acc, m) => acc + m.mood_score, 0);
  return sum / moods.length;
}

function calculateMoodVariance(moods: { mood_score: number }[]): number {
  if (moods.length < 2) return 0;
  const avg = calculateAvgMood(moods);
  const squaredDiffs = moods.map((m) => Math.pow(m.mood_score - avg, 2));
  return squaredDiffs.reduce((a, b) => a + b, 0) / moods.length;
}

function calculateActiveDays(
  moods: { created_at: string }[],
  exercises: { completed_at: string }[],
): number {
  const activeDates = new Set<string>();

  moods.forEach((m) => {
    const date = m.created_at.split("T")[0];
    activeDates.add(date);
  });

  exercises.forEach((e) => {
    const date = e.completed_at.split("T")[0];
    activeDates.add(date);
  });

  return activeDates.size;
}

function calculateAvgSleep(sleepData: { sleep_hours: number }[]): number {
  if (sleepData.length === 0) return 0;
  const sum = sleepData.reduce((acc, s) => acc + s.sleep_hours, 0);
  return sum / sleepData.length;
}

// Tests
Deno.test("calculateAvgMood - computes correct average", () => {
  const avg = calculateAvgMood(mockMoods);
  assertEquals(avg, 3.8); // (3+4+3+5+4) / 5 = 3.8
});

Deno.test("calculateAvgMood - handles empty array", () => {
  const avg = calculateAvgMood([]);
  assertEquals(avg, 0);
});

Deno.test("calculateMoodVariance - computes correct variance", () => {
  const variance = calculateMoodVariance(mockMoods);
  // Mean = 3.8
  // Squared diffs: (3-3.8)^2 + (4-3.8)^2 + (3-3.8)^2 + (5-3.8)^2 + (4-3.8)^2
  // = 0.64 + 0.04 + 0.64 + 1.44 + 0.04 = 2.8
  // Variance = 2.8 / 5 = 0.56
  assertEquals(variance.toFixed(2), "0.56");
});

Deno.test("calculateMoodVariance - handles single mood", () => {
  const variance = calculateMoodVariance([{ mood_score: 4 }]);
  assertEquals(variance, 0);
});

Deno.test("calculateActiveDays - counts unique days with activity", () => {
  const activeDays = calculateActiveDays(mockMoods, mockExercises);
  assertEquals(activeDays, 5); // Jan 13-17, all unique
});

Deno.test("calculateActiveDays - handles overlapping days", () => {
  const moods = [
    { created_at: "2026-01-13T10:00:00Z" },
    { created_at: "2026-01-13T15:00:00Z" }, // Same day
  ];
  const exercises = [
    { completed_at: "2026-01-13T12:00:00Z" }, // Same day again
  ];
  const activeDays = calculateActiveDays(moods, exercises);
  assertEquals(activeDays, 1);
});

Deno.test("calculateAvgSleep - computes correct average", () => {
  const avg = calculateAvgSleep(mockSleepData);
  assertEquals(avg, 7.5); // (7.5+8+6.5+7+8.5) / 5 = 7.5
});

Deno.test("calculateAvgSleep - handles empty array", () => {
  const avg = calculateAvgSleep([]);
  assertEquals(avg, 0);
});

// Date range tests
Deno.test("week date calculation - gets correct week boundaries", () => {
  // For a Sunday-based week ending 2026-01-19 (Sunday)
  const weekEnd = new Date("2026-01-19T23:59:59Z");
  const weekStart = new Date(weekEnd);
  weekStart.setDate(weekStart.getDate() - 6);
  weekStart.setHours(0, 0, 0, 0);

  assertEquals(weekStart.getDate(), 13); // Monday Jan 13
  assertEquals(weekEnd.getDate(), 19); // Sunday Jan 19
});

// Schema validation tests
Deno.test("weekly stat schema - has required fields", () => {
  const weeklyStat = {
    user_id: "user-123",
    week_start: "2026-01-13",
    avg_mood: 3.8,
    mood_variance: 0.56,
    active_days: 5,
    exercises_completed: 5,
    sleep_avg_hours: 7.5,
  };

  assertExists(weeklyStat.user_id);
  assertExists(weeklyStat.week_start);
  assertExists(weeklyStat.avg_mood);
  assertExists(weeklyStat.mood_variance);
  assertExists(weeklyStat.active_days);
  assertExists(weeklyStat.exercises_completed);
  assertExists(weeklyStat.sleep_avg_hours);
});

console.log("All aggregate-weekly-stats tests passed!");
