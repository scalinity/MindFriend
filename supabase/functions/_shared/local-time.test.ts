import { assertEquals } from "jsr:@std/assert@1.0.19";
import { knownTimeZone, localHour, timeOfDayBadgeEarned } from "./local-time.ts";

// 13 November 2026, 7:48 PM in New York: the time Night Owl was awarded in production.
const evening = new Date("2026-11-14T00:48:54Z");

Deno.test("Night Owl is not earned in the evening for a profile still on the UTC default", () => {
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "UTC", evening), false);
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", null, evening), false);
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "Not/AZone", evening), false);
});

Deno.test("Night Owl follows the synced local time", () => {
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "America/New_York", evening), false);
  const afterMidnight = new Date("2026-11-14T05:10:00Z"); // 12:10 AM in New York
  assertEquals(localHour("America/New_York", afterMidnight), 0);
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "America/New_York", afterMidnight), true);
  const fourFifty = new Date("2026-11-14T09:50:00Z"); // 4:50 AM
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "America/New_York", fourFifty), true);
});

Deno.test("Early Bird is the 5 AM hour, local", () => {
  const fiveFifteen = new Date("2026-11-14T10:15:00Z"); // 5:15 AM in New York
  assertEquals(timeOfDayBadgeEarned("activity_before_6am", "America/New_York", fiveFifteen), true);
  assertEquals(timeOfDayBadgeEarned("activity_after_midnight", "America/New_York", fiveFifteen), false);
  // Midnight UTC is 7 PM in New York: not early.
  assertEquals(timeOfDayBadgeEarned("activity_before_6am", "America/New_York", new Date("2026-11-14T05:30:00Z")), false);
  assertEquals(timeOfDayBadgeEarned("activity_before_6am", "UTC", new Date("2026-11-14T05:30:00Z")), false);
});

Deno.test("only a real, synced zone is known", () => {
  assertEquals(knownTimeZone("UTC"), null);
  assertEquals(knownTimeZone(""), null);
  assertEquals(knownTimeZone("Europe/London"), "Europe/London");
});
