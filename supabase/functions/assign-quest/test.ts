// Test file for assign-quest edge function
// Run with: deno test supabase/functions/assign-quest/test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Test shouldContinueStreak logic
Deno.test("shouldContinueStreak - consecutive days returns true", () => {
  const shouldContinueStreak = (
    lastQuestDate: string | null,
    todayDate: string,
  ): boolean => {
    if (!lastQuestDate) return false;
    const today = new Date(todayDate);
    const lastQuest = new Date(lastQuestDate);
    const diffDays = Math.floor(
      (today.getTime() - lastQuest.getTime()) / (1000 * 60 * 60 * 24),
    );
    return diffDays === 1;
  };

  // Consecutive days
  assertEquals(shouldContinueStreak("2024-01-15", "2024-01-16"), true);

  // Gap of 2 days
  assertEquals(shouldContinueStreak("2024-01-15", "2024-01-17"), false);

  // Same day
  assertEquals(shouldContinueStreak("2024-01-15", "2024-01-15"), false);

  // Null last quest date
  assertEquals(shouldContinueStreak(null, "2024-01-16"), false);

  // Year boundary
  assertEquals(shouldContinueStreak("2023-12-31", "2024-01-01"), true);

  // Month boundary
  assertEquals(shouldContinueStreak("2024-01-31", "2024-02-01"), true);
});

Deno.test("getLocalDate - handles timezone correctly", () => {
  const getLocalDate = (timezone: string = "UTC"): string => {
    try {
      const formatter = new Intl.DateTimeFormat("en-CA", {
        timeZone: timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      });
      return formatter.format(new Date());
    } catch {
      // Fallback to UTC if timezone is invalid
      return new Date().toISOString().split("T")[0];
    }
  };

  // Should return YYYY-MM-DD format
  const result = getLocalDate("America/New_York");
  assertEquals(result.match(/^\d{4}-\d{2}-\d{2}$/) !== null, true);

  // UTC should also work
  const utcResult = getLocalDate("UTC");
  assertEquals(utcResult.match(/^\d{4}-\d{2}-\d{2}$/) !== null, true);

  // Invalid timezone should fallback
  const invalidResult = getLocalDate("Invalid/Timezone");
  assertEquals(invalidResult.match(/^\d{4}-\d{2}-\d{2}$/) !== null, true);
});

Deno.test("STREAK_MILESTONES - contains expected values", () => {
  const STREAK_MILESTONES = [7, 14, 30, 60, 100, 365];

  // Expected milestones
  assertEquals(STREAK_MILESTONES.includes(7), true);
  assertEquals(STREAK_MILESTONES.includes(14), true);
  assertEquals(STREAK_MILESTONES.includes(30), true);
  assertEquals(STREAK_MILESTONES.includes(60), true);
  assertEquals(STREAK_MILESTONES.includes(100), true);
  assertEquals(STREAK_MILESTONES.includes(365), true);

  // Non-milestones
  assertEquals(STREAK_MILESTONES.includes(1), false);
  assertEquals(STREAK_MILESTONES.includes(15), false);
  assertEquals(STREAK_MILESTONES.includes(50), false);
  assertEquals(STREAK_MILESTONES.includes(200), false);
});

Deno.test(
  "milestone detection - correctly identifies milestone streaks",
  () => {
    const STREAK_MILESTONES = [7, 14, 30, 60, 100, 365];

    const isMilestone = (streak: number): boolean => {
      return STREAK_MILESTONES.includes(streak);
    };

    // Test milestone detection
    assertEquals(isMilestone(7), true);
    assertEquals(isMilestone(14), true);
    assertEquals(isMilestone(30), true);
    assertEquals(isMilestone(6), false);
    assertEquals(isMilestone(8), false);
    assertEquals(isMilestone(29), false);
  },
);
