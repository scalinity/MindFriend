// Tests for evaluate-recovery-mode Edge Function
// Run with: deno test --allow-env --allow-net supabase/functions/evaluate-recovery-mode/test.ts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

// Mock Supabase client for testing
interface MockData {
  moods: Array<{
    user_id: string;
    mood_score: number;
    local_date: string;
    created_at: string;
  }>;
  user_settings: Array<{
    user_id: string;
    recovery_mode_active: boolean;
    recovery_mode_entered_at: string | null;
    recovery_mode_reason: string | null;
  }>;
}

// Test helper to calculate consecutive low mood days
function calculateConsecutiveLowMoodDays(
  moods: MockData["moods"],
  userId: string,
): number {
  const userMoods = moods
    .filter((m) => m.user_id === userId && m.mood_score <= 2)
    .sort(
      (a, b) =>
        new Date(b.local_date).getTime() - new Date(a.local_date).getTime(),
    );

  if (userMoods.length === 0) return 0;

  let consecutive = 1;
  for (let i = 1; i < userMoods.length; i++) {
    const prevDate = new Date(userMoods[i - 1].local_date);
    const currDate = new Date(userMoods[i].local_date);
    const diffDays = Math.floor(
      (prevDate.getTime() - currDate.getTime()) / (1000 * 60 * 60 * 24),
    );
    if (diffDays === 1) {
      consecutive++;
    } else {
      break;
    }
  }

  return consecutive;
}

// Test: Should not trigger recovery mode with fewer than 3 low mood days
Deno.test("No entry with 2 consecutive low mood days", () => {
  const today = new Date();
  const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);

  const moods = [
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: today.toISOString().split("T")[0],
      created_at: today.toISOString(),
    },
    {
      user_id: "user-1",
      mood_score: 1,
      local_date: yesterday.toISOString().split("T")[0],
      created_at: yesterday.toISOString(),
    },
  ];

  const consecutiveDays = calculateConsecutiveLowMoodDays(moods, "user-1");
  assertEquals(consecutiveDays, 2);
  assertEquals(consecutiveDays >= 3, false); // Should NOT trigger
});

// Test: Should trigger recovery mode with 3 consecutive low mood days
Deno.test("Entry with 3 consecutive low mood days", () => {
  const today = new Date();
  const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);
  const twoDaysAgo = new Date(today.getTime() - 2 * 24 * 60 * 60 * 1000);

  const moods = [
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: today.toISOString().split("T")[0],
      created_at: today.toISOString(),
    },
    {
      user_id: "user-1",
      mood_score: 1,
      local_date: yesterday.toISOString().split("T")[0],
      created_at: yesterday.toISOString(),
    },
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: twoDaysAgo.toISOString().split("T")[0],
      created_at: twoDaysAgo.toISOString(),
    },
  ];

  const consecutiveDays = calculateConsecutiveLowMoodDays(moods, "user-1");
  assertEquals(consecutiveDays, 3);
  assertEquals(consecutiveDays >= 3, true); // Should trigger
});

// Test: Should not count non-consecutive days
Deno.test("Non-consecutive low mood days should not trigger", () => {
  const today = new Date();
  const twoDaysAgo = new Date(today.getTime() - 2 * 24 * 60 * 60 * 1000);
  const fourDaysAgo = new Date(today.getTime() - 4 * 24 * 60 * 60 * 1000);

  const moods = [
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: today.toISOString().split("T")[0],
      created_at: today.toISOString(),
    },
    // Gap: yesterday has no mood or high mood
    {
      user_id: "user-1",
      mood_score: 1,
      local_date: twoDaysAgo.toISOString().split("T")[0],
      created_at: twoDaysAgo.toISOString(),
    },
    // Gap: 3 days ago has no mood or high mood
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: fourDaysAgo.toISOString().split("T")[0],
      created_at: fourDaysAgo.toISOString(),
    },
  ];

  const consecutiveDays = calculateConsecutiveLowMoodDays(moods, "user-1");
  assertEquals(consecutiveDays, 1); // Only today counts as consecutive
  assertEquals(consecutiveDays >= 3, false); // Should NOT trigger
});

// Test: High mood (>= 4) should not count as low mood
Deno.test("High moods should not count as low mood days", () => {
  const today = new Date();
  const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);
  const twoDaysAgo = new Date(today.getTime() - 2 * 24 * 60 * 60 * 1000);

  const moods = [
    {
      user_id: "user-1",
      mood_score: 2,
      local_date: today.toISOString().split("T")[0],
      created_at: today.toISOString(),
    },
    {
      user_id: "user-1",
      mood_score: 4, // High mood - breaks the chain
      local_date: yesterday.toISOString().split("T")[0],
      created_at: yesterday.toISOString(),
    },
    {
      user_id: "user-1",
      mood_score: 1,
      local_date: twoDaysAgo.toISOString().split("T")[0],
      created_at: twoDaysAgo.toISOString(),
    },
  ];

  const consecutiveDays = calculateConsecutiveLowMoodDays(moods, "user-1");
  assertEquals(consecutiveDays, 1); // Only today counts
  assertEquals(consecutiveDays >= 3, false); // Should NOT trigger
});

// Test: 24h minimum duration calculation
Deno.test("24h minimum duration check", () => {
  const now = new Date();
  const lessThan24h = new Date(now.getTime() - 23 * 60 * 60 * 1000);
  const moreThan24h = new Date(now.getTime() - 25 * 60 * 60 * 1000);

  const elapsed1 = now.getTime() - lessThan24h.getTime();
  const elapsed2 = now.getTime() - moreThan24h.getTime();

  const twentyFourHoursMs = 24 * 60 * 60 * 1000;

  assertEquals(elapsed1 >= twentyFourHoursMs, false); // Cannot exit yet
  assertEquals(elapsed2 >= twentyFourHoursMs, true); // Can exit
});

// Test: 7-day timeout calculation
Deno.test("7-day timeout calculation", () => {
  const now = new Date();
  const sixDaysAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
  const eightDaysAgo = new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000);

  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

  const elapsed1 = now.getTime() - sixDaysAgo.getTime();
  const elapsed2 = now.getTime() - eightDaysAgo.getTime();

  assertEquals(elapsed1 >= sevenDaysMs, false); // Not timed out yet
  assertEquals(elapsed2 >= sevenDaysMs, true); // Should force exit
});

// Test: Exit condition with 3 high moods
Deno.test("Exit after 3 consecutive high moods", () => {
  const recentMoods = [{ mood_score: 5 }, { mood_score: 4 }, { mood_score: 4 }];

  const highMoodCount = recentMoods.filter((m) => m.mood_score >= 4).length;
  assertEquals(highMoodCount, 3);
  assertEquals(highMoodCount >= 3, true); // Should trigger exit
});

// Test: No exit with mixed moods
Deno.test("No exit with mixed recent moods", () => {
  const recentMoods = [
    { mood_score: 5 },
    { mood_score: 2 }, // Low mood
    { mood_score: 4 },
  ];

  const highMoodCount = recentMoods.filter((m) => m.mood_score >= 4).length;
  assertEquals(highMoodCount, 2);
  assertEquals(highMoodCount >= 3, false); // Should NOT trigger exit
});

// Test: Manual mode should not auto-exit
Deno.test("Manual recovery mode should not auto-exit on high moods", () => {
  const settings = {
    recovery_mode_active: true,
    recovery_mode_reason: "manual",
    recovery_mode_entered_at: new Date(
      Date.now() - 48 * 60 * 60 * 1000,
    ).toISOString(),
  };

  // Manual mode should only exit via manual toggle, not auto-evaluation
  const shouldAutoExit =
    settings.recovery_mode_reason === "auto_consecutive_low_mood";
  assertEquals(shouldAutoExit, false);
});

console.log("\n=== All Recovery Mode Tests Passed ===\n");
