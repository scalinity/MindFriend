// Tests for notification utility functions
// Run with: deno test --allow-env supabase/functions/_shared/notification-utils.test.ts

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isInQuietHours,
  buildNotificationContent,
  getMoodTrendMessage,
  type NotificationType,
} from "./notification-utils.ts";

// ============================================================================
// isInQuietHours tests
// ============================================================================

Deno.test("isInQuietHours - returns false when quiet hours not set", () => {
  assertEquals(isInQuietHours(12, null, null), false);
  assertEquals(isInQuietHours(12, "22:00", null), false);
  assertEquals(isInQuietHours(12, null, "08:00"), false);
});

Deno.test("isInQuietHours - normal range (no midnight wrap)", () => {
  // Quiet hours: 09:00 - 17:00
  assertEquals(isInQuietHours(8, "09:00", "17:00"), false); // Before start
  assertEquals(isInQuietHours(9, "09:00", "17:00"), true); // At start
  assertEquals(isInQuietHours(10, "09:00", "17:00"), true); // During
  assertEquals(isInQuietHours(16, "09:00", "17:00"), true); // Near end
  assertEquals(isInQuietHours(17, "09:00", "17:00"), false); // At end (exclusive)
  assertEquals(isInQuietHours(18, "09:00", "17:00"), false); // After end
});

Deno.test("isInQuietHours - midnight wrap-around", () => {
  // Quiet hours: 22:00 - 08:00 (overnight)
  assertEquals(isInQuietHours(21, "22:00", "08:00"), false); // Before start
  assertEquals(isInQuietHours(22, "22:00", "08:00"), true); // At start
  assertEquals(isInQuietHours(23, "22:00", "08:00"), true); // Before midnight
  assertEquals(isInQuietHours(0, "22:00", "08:00"), true); // Midnight
  assertEquals(isInQuietHours(3, "22:00", "08:00"), true); // After midnight
  assertEquals(isInQuietHours(7, "22:00", "08:00"), true); // Near end
  assertEquals(isInQuietHours(8, "22:00", "08:00"), false); // At end (exclusive)
  assertEquals(isInQuietHours(12, "22:00", "08:00"), false); // During day
});

Deno.test("isInQuietHours - edge cases", () => {
  // Same hour start/end (empty range)
  assertEquals(isInQuietHours(12, "12:00", "12:00"), false);

  // Hour 0 boundary
  assertEquals(isInQuietHours(0, "23:00", "06:00"), true);
  assertEquals(isInQuietHours(23, "23:00", "06:00"), true);
  assertEquals(isInQuietHours(6, "23:00", "06:00"), false);

  // Single hour range
  assertEquals(isInQuietHours(14, "14:00", "15:00"), true);
  assertEquals(isInQuietHours(15, "14:00", "15:00"), false);
});

// ============================================================================
// buildNotificationContent tests
// ============================================================================

Deno.test("buildNotificationContent - circle_activity", () => {
  const content = buildNotificationContent("circle_activity", {
    senderName: "Alice",
    circleId: "123",
  });

  assertEquals(content.title, "Circle Update");
  assertStringIncludes(content.body, "Alice");
  assertStringIncludes(content.deepLink, "mindfriend://circle/123");
});

Deno.test(
  "buildNotificationContent - circle_activity with default sender",
  () => {
    const content = buildNotificationContent("circle_activity", {
      circleId: "456",
    });

    assertStringIncludes(content.body, "Someone");
  },
);

Deno.test("buildNotificationContent - hug", () => {
  const content = buildNotificationContent("hug", {
    senderName: "Bob",
    circleId: "789",
  });

  assertStringIncludes(content.title, "hug");
  assertStringIncludes(content.body, "Bob");
  assertStringIncludes(content.deepLink, "mindfriend://circle/789");
});

Deno.test("buildNotificationContent - streak_risk urgency 0", () => {
  const content = buildNotificationContent("streak_risk", {
    streak: 5,
    urgency: 0,
  });

  assertStringIncludes(content.title, "Streak");
  assertStringIncludes(content.body, "5 days");
  assertStringIncludes(content.body, "day 6"); // streak + 1
  assertEquals(content.deepLink, "mindfriend://quest");
});

Deno.test("buildNotificationContent - streak_risk urgency 1", () => {
  const content = buildNotificationContent("streak_risk", {
    streak: 10,
    urgency: 1,
  });

  assertStringIncludes(content.body, "10 day streak");
  assertStringIncludes(content.body, "at risk");
});

Deno.test("buildNotificationContent - weekly_summary", () => {
  const content = buildNotificationContent("weekly_summary", {
    checkins: 5,
    quests: 7,
    moodMessage: "Great week!",
  });

  assertStringIncludes(content.title, "Week");
  assertStringIncludes(content.body, "5 check-ins");
  assertStringIncludes(content.body, "7 quests");
  assertStringIncludes(content.body, "Great week!");
  assertEquals(content.deepLink, "mindfriend://insights");
});

Deno.test("buildNotificationContent - challenge", () => {
  const content = buildNotificationContent("challenge", {
    completedCount: 3,
    totalMembers: 5,
    circleId: "abc",
  });

  assertStringIncludes(content.title, "Challenge");
  assertStringIncludes(content.body, "3/5");
  assertStringIncludes(content.deepLink, "mindfriend://circle/abc");
});

Deno.test("buildNotificationContent - unknown type fallback", () => {
  // Test with a type cast to simulate unknown type
  const content = buildNotificationContent("unknown" as NotificationType, {});

  assertEquals(content.title, "MindFriend");
  assertStringIncludes(content.deepLink, "mindfriend://");
});

// ============================================================================
// getMoodTrendMessage tests
// ============================================================================

Deno.test("getMoodTrendMessage - null values", () => {
  assertEquals(
    getMoodTrendMessage(null, null),
    "Keep tracking to see your trends!",
  );
  assertEquals(
    getMoodTrendMessage("improving", null),
    "Keep tracking to see your trends!",
  );
  assertEquals(
    getMoodTrendMessage(null, 7.5),
    "Keep tracking to see your trends!",
  );
});

Deno.test("getMoodTrendMessage - improving", () => {
  const msg = getMoodTrendMessage("improving", 8.0);
  assertStringIncludes(msg, "trending up");
});

Deno.test("getMoodTrendMessage - stable", () => {
  const msg = getMoodTrendMessage("stable", 6.5);
  assertStringIncludes(msg, "steady");
});

Deno.test("getMoodTrendMessage - declining", () => {
  const msg = getMoodTrendMessage("declining", 4.0);
  assertStringIncludes(msg, "tough week");
});

Deno.test("getMoodTrendMessage - unknown trend", () => {
  const msg = getMoodTrendMessage("unknown_trend", 5.0);
  assertEquals(msg, "");
});
