// Test file for send-notification edge function
// Run with: deno test supabase/functions/send-notification/test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("isInQuietHours - normal range (e.g., 9pm to 8am)", () => {
  const isInQuietHours = (
    currentHour: number,
    quietStart: string | null,
    quietEnd: string | null,
  ): boolean => {
    if (!quietStart || !quietEnd) return false;
    const startHour = parseInt(quietStart.split(":")[0], 10);
    const endHour = parseInt(quietEnd.split(":")[0], 10);
    if (startHour > endHour) {
      // Wraps around midnight (e.g., 22:00 to 08:00)
      return currentHour >= startHour || currentHour < endHour;
    } else {
      // Same day range (e.g., 08:00 to 17:00)
      return currentHour >= startHour && currentHour < endHour;
    }
  };

  // 22:00 to 08:00 quiet hours (wraps around midnight)
  assertEquals(isInQuietHours(23, "22:00", "08:00"), true); // Late night
  assertEquals(isInQuietHours(3, "22:00", "08:00"), true); // Early morning
  assertEquals(isInQuietHours(12, "22:00", "08:00"), false); // Midday
  assertEquals(isInQuietHours(8, "22:00", "08:00"), false); // Exactly at end
  assertEquals(isInQuietHours(22, "22:00", "08:00"), true); // Exactly at start
  assertEquals(isInQuietHours(21, "22:00", "08:00"), false); // Just before start

  // 08:00 to 17:00 quiet hours (same day)
  assertEquals(isInQuietHours(12, "08:00", "17:00"), true); // Midday
  assertEquals(isInQuietHours(7, "08:00", "17:00"), false); // Before start
  assertEquals(isInQuietHours(17, "08:00", "17:00"), false); // At end
  assertEquals(isInQuietHours(20, "08:00", "17:00"), false); // After end

  // No quiet hours set
  assertEquals(isInQuietHours(23, null, null), false);
  assertEquals(isInQuietHours(12, null, "08:00"), false);
  assertEquals(isInQuietHours(12, "22:00", null), false);
});

Deno.test("buildNotificationContent - hug type", () => {
  type NotificationContent = { title: string; body: string; deepLink: string };

  const buildNotificationContent = (
    type: string,
    data: Record<string, unknown>,
  ): NotificationContent => {
    if (type === "hug") {
      return {
        title: "You got a hug! 🤗",
        body: `${data.senderName || "Someone"} sent you some love`,
        deepLink: `mindfriend://circle/${data.circleId || ""}`,
      };
    }
    return { title: "", body: "", deepLink: "" };
  };

  // With full data
  const result = buildNotificationContent("hug", {
    senderName: "Alice",
    circleId: "123",
  });
  assertEquals(result.title, "You got a hug! 🤗");
  assertEquals(result.body, "Alice sent you some love");
  assertEquals(result.deepLink, "mindfriend://circle/123");

  // With missing sender name
  const resultNoName = buildNotificationContent("hug", { circleId: "456" });
  assertEquals(resultNoName.body, "Someone sent you some love");
  assertEquals(resultNoName.deepLink, "mindfriend://circle/456");

  // With missing circle id
  const resultNoCircle = buildNotificationContent("hug", {
    senderName: "Bob",
  });
  assertEquals(resultNoCircle.deepLink, "mindfriend://circle/");
});

Deno.test("buildNotificationContent - streak_risk type", () => {
  type NotificationContent = { title: string; body: string; deepLink: string };

  const buildNotificationContent = (
    type: string,
    data: Record<string, unknown>,
  ): NotificationContent => {
    if (type === "streak_risk") {
      const urgency = (data.urgency as number) || 0;
      const streak = (data.streak as number) || 0;
      const messages = [
        `You've been consistent for ${streak} days. Tomorrow is day ${streak + 1}!`,
        `Your ${streak} day streak is at risk - check in to keep it going`,
      ];
      return {
        title: "🔥 Streak Alert",
        body: messages[urgency] || messages[0],
        deepLink: "mindfriend://quest",
      };
    }
    return { title: "", body: "", deepLink: "" };
  };

  // Encouraging (urgency 0)
  const result = buildNotificationContent("streak_risk", {
    streak: 7,
    urgency: 0,
  });
  assertEquals(result.title, "🔥 Streak Alert");
  assertEquals(
    result.body,
    "You've been consistent for 7 days. Tomorrow is day 8!",
  );
  assertEquals(result.deepLink, "mindfriend://quest");

  // Warning (urgency 1)
  const resultWarning = buildNotificationContent("streak_risk", {
    streak: 14,
    urgency: 1,
  });
  assertEquals(
    resultWarning.body,
    "Your 14 day streak is at risk - check in to keep it going",
  );
});

Deno.test("buildNotificationContent - challenge type", () => {
  type NotificationContent = { title: string; body: string; deepLink: string };

  const buildNotificationContent = (
    type: string,
    data: Record<string, unknown>,
  ): NotificationContent => {
    if (type === "challenge") {
      const completed = (data.completedCount as number) || 0;
      const total = (data.totalMembers as number) || 0;
      return {
        title: "Challenge Update 🎯",
        body: `${completed}/${total} completed today's challenge`,
        deepLink: `mindfriend://circle/${data.circleId || ""}`,
      };
    }
    return { title: "", body: "", deepLink: "" };
  };

  const result = buildNotificationContent("challenge", {
    completedCount: 3,
    totalMembers: 5,
    circleId: "abc123",
  });
  assertEquals(result.title, "Challenge Update 🎯");
  assertEquals(result.body, "3/5 completed today's challenge");
  assertEquals(result.deepLink, "mindfriend://circle/abc123");
});

Deno.test("constant-time comparison - XOR technique", () => {
  const constantTimeCompare = (a: string, b: string): boolean => {
    const aBytes = new TextEncoder().encode(a);
    const bBytes = new TextEncoder().encode(b);

    if (aBytes.length !== bBytes.length) {
      return false;
    }

    let diff = 0;
    for (let i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff === 0;
  };

  // Equal strings
  assertEquals(constantTimeCompare("secret", "secret"), true);
  assertEquals(constantTimeCompare("abc123", "abc123"), true);

  // Different strings
  assertEquals(constantTimeCompare("secret", "Secret"), false);
  assertEquals(constantTimeCompare("abc", "abcd"), false);
  assertEquals(constantTimeCompare("abcd", "abc"), false);
  assertEquals(constantTimeCompare("", "a"), false);
  assertEquals(constantTimeCompare("a", ""), false);

  // Empty strings
  assertEquals(constantTimeCompare("", ""), true);
});
