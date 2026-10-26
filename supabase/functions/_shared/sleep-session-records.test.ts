import { assertEquals } from "jsr:@std/assert@1.0.19";
import { withoutContainedSleepImports } from "./sleep-session-records.ts";
const full = {
  id: "a",
  user_id: "owner",
  source: "healthkit",
  bedtime: "2026-10-24T14:00:00Z",
  wake_time: "2026-10-25T09:00:00Z",
  time_in_bed_minutes: 1140,
  time_asleep_minutes: 1080,
};
Deno.test("complete owned import supersedes both contained fragments without mutation", () => {
  const entries = [full, {
    ...full,
    id: "b",
    wake_time: "2026-10-25T04:00:00Z",
  }, { ...full, id: "c", bedtime: "2026-10-25T04:00:00Z" }];
  assertEquals(withoutContainedSleepImports(entries), [full]);
  assertEquals(entries.length, 3);
});
Deno.test("manual and other owners remain separate; duplicate bounds have one stable winner", () => {
  const manual = { ...full, id: "manual", source: "manual" };
  const other = { ...full, id: "other", user_id: "other" };
  const entries = [manual, full, { ...full, id: "z" }, other];
  assertEquals(withoutContainedSleepImports(entries), [manual, full, other]);
  assertEquals(withoutContainedSleepImports(entries.toReversed()), [
    other,
    full,
    manual,
  ]);
});
Deno.test("incomplete or invalid enclosing import cannot hide a valid record", () => {
  for (const bad of [null, 0, 2000]) {
    const invalid = { ...full, id: "bad", time_asleep_minutes: bad };
    const fragment = {
      ...full,
      id: "fragment",
      bedtime: "2026-10-25T00:00:00Z",
    };
    assertEquals(withoutContainedSleepImports([invalid, fragment]).length, 2);
  }
});
Deno.test("newest equal-bounds import wins and nested records are counted once", () => {
  const fresh = { ...full, id: "new", updated_at: "2026-10-25T20:00:00Z" };
  const nested = { ...full, id: "nested", bedtime: "2026-10-25T04:00:00Z" };
  assertEquals(withoutContainedSleepImports([full, nested, fresh]), [fresh]);
});
