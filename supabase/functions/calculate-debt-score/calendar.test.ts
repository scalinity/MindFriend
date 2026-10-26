import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import { checkedTimeZone, localDate, localDayStart } from "./calendar.ts";
Deno.test("Eastern day boundary differs from the UTC date after local evening", () => {
  const instant = new Date("2026-10-26T00:30:00Z");
  assertEquals(localDate(instant, "America/New_York"), "2026-10-25");
  assertEquals(localDate(instant, "UTC"), "2026-10-26");
  assertEquals(localDayStart("2026-10-25", "America/New_York"), "2026-10-25T04:00:00.000Z");
});
Deno.test("spring and autumn local days contain 23 and 25 actual hours", () => {
  for (const [day, next, hours] of [["2026-03-08", "2026-03-09", 23], ["2026-11-01", "2026-11-02", 25]] as const) {
    assertEquals((Date.parse(localDayStart(next, "America/New_York")) - Date.parse(localDayStart(day, "America/New_York"))) / 3600000, hours);
  }
});
Deno.test("extreme zones, fractional offsets and a skipped midnight use the correct instant", () => {
  assertEquals(localDayStart("2026-10-25", "Pacific/Kiritimati"), "2026-10-24T10:00:00.000Z");
  assertEquals(localDayStart("2026-10-25", "Etc/GMT+12"), "2026-10-25T12:00:00.000Z");
  assertEquals(localDayStart("2026-10-25", "Asia/Kathmandu"), "2026-10-24T18:15:00.000Z");
  assertEquals(localDayStart("2026-09-06", "America/Santiago"), "2026-09-06T04:00:00.000Z");
});
Deno.test("invalid zones, invalid dates and a skipped calendar date fail explicitly", () => {
  for (const zone of ["America/NotAZone", "", null, 42]) assertThrows(() => checkedTimeZone(zone));
  assertThrows(() => localDayStart("2026-02-30", "UTC"));
  assertThrows(() => localDayStart("2011-12-30", "Pacific/Apia"));
});
